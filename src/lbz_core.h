// Platform core for the macOS port: settings, offline cache, HTTP submission.
// Uses only Apple frameworks (Foundation) - no foobar2000 SDK here.
#pragma once
#import <Foundation/Foundation.h>
#include <string>

namespace lbz
{
	extern NSString* const kDefaultApiUrl;

	struct Settings
	{
		bool enabled = false;
		bool artistFirst = true;     // only the first artist value
		bool libraryOnly = false;    // only tracks in the Media Library
		bool clientDetails = true;   // send player / component version
		std::string token;
		std::string apiUrl;          // empty = official ListenBrainz
	};

	typedef void (*LogFn)(const char* message);
	void setLogger(LogFn fn);

	Settings settings();                      // cached copy
	void saveSettings(const Settings& s);
	void setEnabled(bool enabled);

	bool isUuid(const std::string& s);
	bool isDefaultServer(const Settings& s);
	bool isValidToken(const Settings& s);

	// Fire-and-forget; all run asynchronously.
	void submitPlayingNow(NSDictionary* trackMetadata);
	void submitListen(NSDictionary* trackMetadata, long long listenedAt);
	void flushCache();

	// Calls done on a background thread.
	void verifyToken(void (^done)(bool valid, NSString* message));
}
