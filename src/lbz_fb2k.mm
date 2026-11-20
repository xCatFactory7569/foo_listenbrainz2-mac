// foobar2000 glue: component registration, play callback, menu commands.
#import <Cocoa/Cocoa.h>
#include <foobar2000/SDK/foobar2000.h>
#include <ctime>
#include <cmath>
#include <string>
#include <vector>
#import "lbz_core.h"

namespace lbz
{
	static constexpr const char* component_name = "ListenBrainz 2";
	static constexpr const char* component_version = "1.5.0-mac1";
	static constexpr const char* component_info =
		"macOS port of foo_listenbrainz2.\n"
		"Copyright (C) 2020 marc2003\nCopyright (C) 2022-2023 phw\n"
		"https://github.com/phw/foo_listenbrainz2\n\n"
		"Settings: Preferences > Tools > ListenBrainz 2";

	DECLARE_COMPONENT_VERSION(component_name, component_version, component_info);

	static const GUID guid_menu_toggle = { 0xb6aedf18, 0x6164, 0x4291, { 0x8a, 0x27, 0x72, 0xbd, 0x40, 0x14, 0xd1, 0x77 } };

	static void console_log(const char* message)
	{
		FB2K_console_formatter() << component_name << ": " << message;
	}

	static NSString* ns(const char* s)
	{
		return s ? [NSString stringWithUTF8String:s] : nil;
	}

	struct mbid_map { const char* primary; const char* secondary; const char* name; };
	static const mbid_map mbids[] =
	{
		{ "MUSICBRAINZ_ARTISTID", "MUSICBRAINZ ARTIST ID", "artist_mbids" },
		{ "MUSICBRAINZ_ALBUMID", "MUSICBRAINZ ALBUM ID", "release_mbid" },
		{ "MUSICBRAINZ_RELEASEGROUPID", "MUSICBRAINZ RELEASE GROUP ID", "release_group_mbid" },
		{ "MUSICBRAINZ_RELEASETRACKID", "MUSICBRAINZ RELEASE TRACK ID", "track_mbid" },
		{ "MUSICBRAINZ_TRACKID", "MUSICBRAINZ TRACK ID", "recording_mbid" },
		{ "MUSICBRAINZ_WORKID", "MUSICBRAINZ WORK ID", "work_mbids" },
	};

	static bool uuid_ok(const char* v) { return v && isUuid(v); }

	static NSString* foobar_version()
	{
		id v = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
		return [v isKindOfClass:[NSString class]] ? v : @"unknown";
	}

	class lbz_play_callback : public play_callback_static
	{
	public:
		uint32_t get_flags() override
		{
			return flag_on_playback_new_track | flag_on_playback_time;
		}

		void on_playback_new_track(metadb_handle_ptr handle) override
		{
			m_counter = 0;
			const double length = handle->get_length();
			if (length >= 5.0 && settings().enabled)
			{
				const size_t half = static_cast<size_t>(std::round(length / 2));
				m_target = std::min<size_t>(half, 240U);
				m_listened_at = static_cast<long long>(std::time(nullptr));
			}
			else
			{
				m_target = SIZE_MAX;
				m_listened_at = 0;
			}
		}

		void on_playback_time(double) override
		{
			if (m_target == SIZE_MAX) return;
			m_counter++;
			if (m_counter == 2) submit(false);
			else if (m_counter == m_target) submit(true);
		}

		void on_playback_dynamic_info(const file_info&) override {}
		void on_playback_dynamic_info_track(const file_info&) override {}
		void on_playback_edited(metadb_handle_ptr) override {}
		void on_playback_pause(bool) override {}
		void on_playback_seek(double) override {}
		void on_playback_starting(play_control::t_track_command, bool) override {}
		void on_playback_stop(play_control::t_stop_reason) override {}
		void on_volume_change(float) override {}

	private:
		std::string tag(const file_info& info, const char* name)
		{
			const char* value = info.meta_get(name, 0);
			return value ? std::string(value) : std::string();
		}

		std::string artist_for(const metadb_handle_ptr& handle, const file_info& info, const Settings& s)
		{
			if (s.artistFirst) return tag(info, "artist");
			if (m_obj.is_empty())
			{
				static_api_ptr_t<titleformat_compiler>()->compile_force(m_obj, "[%artist%]");
			}
			pfc::string8 out;
			handle->format_title(nullptr, out, m_obj, nullptr);
			return std::string(out.c_str());
		}

		bool allowed(const metadb_handle_ptr& handle, bool report, const Settings& s)
		{
			if (!s.enabled) return false;
			if (!isValidToken(s))
			{
				if (report) console_log("Token not set. Not submitting.");
				return false;
			}
			if (s.libraryOnly && !static_api_ptr_t<library_manager>()->is_item_in_library(handle))
			{
				if (report) console_log("Track not in Media Library. Not submitting.");
				return false;
			}
			return true;
		}

		NSDictionary* additional_info(const file_info& info, const Settings& s)
		{
			NSMutableDictionary* out = [NSMutableDictionary dictionary];

			auto put = [&](NSString* key, const std::string& v) {
				if (v.empty()) return;
				NSString* str = ns(v.c_str());
				if (str) out[key] = str;
			};
			auto putInt = [&](NSString* key, const std::string& v) {
				if (v.empty()) return;
				try { out[key] = @(std::stoi(v)); }
				catch (const std::exception&) { put(key, v); }
			};

			put(@"albumartist", tag(info, "album artist"));
			put(@"date", tag(info, "date"));
			putInt(@"discnumber", tag(info, "discnumber"));
			put(@"isrc", tag(info, "isrc"));
			putInt(@"totaldiscs", tag(info, "totaldiscs"));
			putInt(@"totaltracks", tag(info, "totaltracks"));
			putInt(@"tracknumber", tag(info, "tracknumber"));

			for (const auto& m : mbids)
			{
				NSString* key = ns(m.name);
				const std::string nm(m.name);
				const bool multi = nm == "artist_mbids" || nm == "work_mbids";
				if (multi)
				{
					size_t idx = info.meta_find(m.primary);
					if (idx == SIZE_MAX) idx = info.meta_find(m.secondary);
					if (idx == SIZE_MAX) continue;
					NSMutableArray* values = [NSMutableArray array];
					const size_t count = info.meta_enum_value_count(idx);
					for (size_t i = 0; i < count; ++i)
					{
						const char* v = info.meta_enum_value(idx, i);
						if (uuid_ok(v)) [values addObject:[ns(v) lowercaseString]];
					}
					if (values.count) out[key] = values;
				}
				else
				{
					const char* v = info.meta_get(m.primary, 0);
					if (!uuid_ok(v)) v = info.meta_get(m.secondary, 0);
					if (uuid_ok(v)) out[key] = [ns(v) lowercaseString];
				}
			}

			const double length = info.get_length();
			if (length > 0.0) out[@"duration_ms"] = @((long long)std::llround(length * 1000.0));

			if (s.clientDetails)
			{
				out[@"media_player"] = @"foobar2000";
				out[@"media_player_version"] = foobar_version();
				out[@"submission_client"] = @"foo_listenbrainz2";
				out[@"submission_client_version"] = ns(component_version);
			}
			return out;
		}

		void submit(bool is_single)
		{
			metadb_handle_ptr handle;
			if (!playback_control::get()->get_now_playing(handle)) return;
			file_info_impl info;
			if (!handle->get_info(info)) return;
			const Settings s = settings();

			const std::string artist = artist_for(handle, info, s);
			const std::string title = tag(info, "title");
			if (artist.empty() || title.empty()) return;
			if (!allowed(handle, is_single, s)) return;

			NSMutableDictionary* meta = [NSMutableDictionary dictionary];
			NSString* a = ns(artist.c_str());
			NSString* t = ns(title.c_str());
			if (!a || !t) return;
			meta[@"artist_name"] = a;
			meta[@"track_name"] = t;
			const char* album = info.meta_get("album", 0);
			if (album && ns(album)) meta[@"release_name"] = ns(album);
			meta[@"additional_info"] = additional_info(info, s);

			if (is_single) submitListen(meta, m_listened_at);
			else submitPlayingNow(meta);
		}

		size_t m_counter = 0;
		size_t m_target = SIZE_MAX;
		long long m_listened_at = 0;
		titleformat_object::ptr m_obj;
	};

	static play_callback_static_factory_t<lbz_play_callback> g_lbz_play_callback_factory;

	class lbz_initquit : public initquit
	{
	public:
		void on_init() override
		{
			setLogger(console_log);
			const Settings s = settings();
			if (isValidToken(s)) flushCache();
		}
		void on_quit() override {}
	};

	static initquit_factory_t<lbz_initquit> g_lbz_initquit_factory;

	class lbz_mainmenu_commands : public mainmenu_commands
	{
	public:
		t_uint32 get_command_count() override { return 1; }

		GUID get_command(t_uint32) override { return guid_menu_toggle; }

		GUID get_parent() override { return mainmenu_groups::playback; }

		void get_name(t_uint32, pfc::string_base& out) override
		{
			out = "Submit to ListenBrainz";
		}

		bool get_description(t_uint32, pfc::string_base& out) override
		{
			out = "Toggle ListenBrainz submissions on/off";
			return true;
		}

		bool get_display(t_uint32 index, pfc::string_base& out, t_uint32& flags) override
		{
			const bool rv = mainmenu_commands::get_display(index, out, flags);
			const Settings s = settings();
			if (!isValidToken(s)) flags |= flag_disabled;
			else if (s.enabled) flags |= flag_checked;
			return rv;
		}

		void execute(t_uint32, ctx_t) override
		{
			const Settings s = settings();
			if (isValidToken(s)) setEnabled(!s.enabled);
		}
	};

	static mainmenu_commands_factory_t<lbz_mainmenu_commands> g_lbz_menu_factory;
}
