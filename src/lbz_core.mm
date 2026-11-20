#import "lbz_core.h"
#include <mutex>

namespace lbz
{
	NSString* const kDefaultApiUrl = @"https://api.listenbrainz.org/1/submit-listens";
	static NSString* const kValidateUrl = @"https://api.listenbrainz.org/1/validate-token";
	static NSString* const kSuite = @"io.github.foo-listenbrainz2.mac";
	static const NSUInteger kBatch = 50;
	static const NSUInteger kCacheMax = 10000;

	static LogFn g_log = nullptr;
	void setLogger(LogFn fn) { g_log = fn; }
	static void logMsg(NSString* msg)
	{
		if (g_log && msg) g_log([msg UTF8String]);
	}
	static void logStd(const std::string& msg)
	{
		if (g_log) g_log(msg.c_str());
	}

	// ---------------------------------------------------------------- settings
	static NSUserDefaults* defs()
	{
		static NSUserDefaults* d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
		return d;
	}
	static std::string toStd(NSString* s) { return s ? std::string([s UTF8String]) : std::string(); }

	static Settings loadFromDisk()
	{
		NSUserDefaults* d = defs();
		Settings s;
		if ([d objectForKey:@"enabled"]) s.enabled = [d boolForKey:@"enabled"];
		if ([d objectForKey:@"artistFirst"]) s.artistFirst = [d boolForKey:@"artistFirst"];
		if ([d objectForKey:@"libraryOnly"]) s.libraryOnly = [d boolForKey:@"libraryOnly"];
		if ([d objectForKey:@"clientDetails"]) s.clientDetails = [d boolForKey:@"clientDetails"];
		s.token = toStd([d stringForKey:@"token"]);
		s.apiUrl = toStd([d stringForKey:@"apiUrl"]);
		return s;
	}

	static std::mutex g_mutex;
	static Settings g_settings;
	static bool g_loaded = false;

	Settings settings()
	{
		std::lock_guard<std::mutex> lock(g_mutex);
		if (!g_loaded) { g_settings = loadFromDisk(); g_loaded = true; }
		return g_settings;
	}

	void saveSettings(const Settings& s)
	{
		NSUserDefaults* d = defs();
		[d setBool:s.enabled forKey:@"enabled"];
		[d setBool:s.artistFirst forKey:@"artistFirst"];
		[d setBool:s.libraryOnly forKey:@"libraryOnly"];
		[d setBool:s.clientDetails forKey:@"clientDetails"];
		[d setObject:[NSString stringWithUTF8String:s.token.c_str()] forKey:@"token"];
		[d setObject:[NSString stringWithUTF8String:s.apiUrl.c_str()] forKey:@"apiUrl"];
		[d synchronize];
		std::lock_guard<std::mutex> lock(g_mutex);
		g_settings = s;
		g_loaded = true;
	}

	void setEnabled(bool enabled)
	{
		Settings s = settings();
		s.enabled = enabled;
		saveSettings(s);
	}

	bool isUuid(const std::string& s)
	{
		if (s.size() != 36) return false;
		for (size_t i = 0; i < 36; ++i)
		{
			const char c = s[i];
			if (i == 8 || i == 13 || i == 18 || i == 23)
			{
				if (c != '-') return false;
			}
			else if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
			{
				return false;
			}
		}
		return true;
	}

	bool isDefaultServer(const Settings& s)
	{
		return s.apiUrl.empty() || s.apiUrl == [kDefaultApiUrl UTF8String];
	}

	bool isValidToken(const Settings& s)
	{
		if (s.token.empty()) return false;
		if (isDefaultServer(s)) return isUuid(s.token);
		return true;
	}

	static NSString* effectiveUrl(const Settings& s)
	{
		if (s.apiUrl.empty()) return kDefaultApiUrl;
		return [NSString stringWithUTF8String:s.apiUrl.c_str()];
	}

	// -------------------------------------------------------------------- HTTP
	struct PostResult
	{
		bool transportOk = false;
		long http = 0;
		bool ok = false;
		bool bad = false;   // server says the submission is malformed (400)
		std::string message;
	};

	static void sendRequest(NSMutableURLRequest* req, void (^done)(const PostResult&))
	{
		[[[NSURLSession sharedSession] dataTaskWithRequest:req
			completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
		{
			PostResult r;
			if (error)
			{
				r.message = toStd(error.localizedDescription);
				done(r);
				return;
			}
			r.transportOk = true;
			r.http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (long)((NSHTTPURLResponse*)response).statusCode : 0;

			id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
			if ([json isKindOfClass:[NSDictionary class]])
			{
				NSDictionary* dict = (NSDictionary*)json;
				id status = dict[@"status"];
				id code = dict[@"code"];
				id err = dict[@"error"];
				r.ok = r.http >= 200 && r.http < 300 && [status isKindOfClass:[NSString class]] && [status isEqualToString:@"ok"];
				r.bad = ([code isKindOfClass:[NSNumber class]] && [code intValue] == 400) || r.http == 400;
				if ([err isKindOfClass:[NSString class]]) r.message = toStd(err);
			}
			else
			{
				r.bad = r.http == 400;
			}
			if (!r.ok && r.message.empty())
			{
				r.message = "Server answered with HTTP status " + std::to_string(r.http);
			}
			done(r);
		}] resume];
	}

	static void postJson(const Settings& s, NSDictionary* body, void (^done)(const PostResult&))
	{
		NSData* data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
		NSURL* url = [NSURL URLWithString:effectiveUrl(s)];
		if (!data || !url)
		{
			PostResult r;
			r.bad = true;
			r.message = "Could not build the request (check the API URL).";
			done(r);
			return;
		}
		NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:url
			cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
		req.HTTPMethod = @"POST";
		[req setValue:[NSString stringWithFormat:@"Token %s", s.token.c_str()] forHTTPHeaderField:@"Authorization"];
		[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
		req.HTTPBody = data;
		sendRequest(req, done);
	}

	// ------------------------------------------------------------------- cache
	// Everything below touching g_cache runs on this serial queue.
	static dispatch_queue_t cacheQueue()
	{
		static dispatch_queue_t q;
		static dispatch_once_t once;
		dispatch_once(&once, ^{ q = dispatch_queue_create("foo_listenbrainz2.cache", DISPATCH_QUEUE_SERIAL); });
		return q;
	}
	static NSMutableArray* g_cache = nil;
	static bool g_flushing = false;

	static void loadCache()
	{
		if (g_cache) return;
		NSArray* a = [defs() arrayForKey:@"cache"];
		g_cache = a ? [a mutableCopy] : [NSMutableArray array];
		if (g_cache.count) logMsg([NSString stringWithFormat:@"Loaded cache with %lu listen(s)", (unsigned long)g_cache.count]);
	}
	static void persistCache()
	{
		[defs() setObject:g_cache forKey:@"cache"];
	}

	static void cacheListen(NSDictionary* listen)
	{
		dispatch_async(cacheQueue(), ^{
			loadCache();
			[g_cache addObject:listen];
			while (g_cache.count > kCacheMax) [g_cache removeObjectAtIndex:0];
			persistCache();
			logMsg([NSString stringWithFormat:@"The cache now contains %lu listen(s)", (unsigned long)g_cache.count]);
		});
	}

	void flushCache()
	{
		dispatch_async(cacheQueue(), ^{
			loadCache();
			if (g_flushing || g_cache.count == 0) return;
			Settings s = settings();
			if (!isValidToken(s)) return;

			const NSUInteger n = MIN(g_cache.count, kBatch);
			NSArray* batch = [g_cache subarrayWithRange:NSMakeRange(0, n)];
			g_flushing = true;
			logMsg([NSString stringWithFormat:@"Now submitting %lu listen(s) from the cache.", (unsigned long)n]);

			NSDictionary* body = @{ @"listen_type": @"import", @"payload": batch };
			postJson(s, body, ^(const PostResult& r) {
				PostResult res = r;
				dispatch_async(cacheQueue(), ^{
					g_flushing = false;
					if (res.ok)
					{
						logMsg(@"Cached listens submitted OK!");
						[g_cache removeObjectsInRange:NSMakeRange(0, MIN(n, g_cache.count))];
						persistCache();
						if (g_cache.count > 0) flushCache();
					}
					else if (res.bad)
					{
						logMsg(@"Submission of the cache was refused because one or more listens were malformed. The cache will now be reset.");
						[g_cache removeAllObjects];
						persistCache();
					}
					else
					{
						logStd("Could not submit cached listens: " + res.message);
					}
				});
			});
		});
	}

	// ------------------------------------------------------------- submissions
	void submitPlayingNow(NSDictionary* meta)
	{
		Settings s = settings();
		NSDictionary* body = @{ @"listen_type": @"playing_now", @"payload": @[ @{ @"track_metadata": meta } ] };
		postJson(s, body, ^(const PostResult&) { /* silent, like the original */ });
	}

	void submitListen(NSDictionary* meta, long long listenedAt)
	{
		Settings s = settings();
		NSDictionary* listen = @{ @"listened_at": @(listenedAt), @"track_metadata": meta };
		NSDictionary* body = @{ @"listen_type": @"single", @"payload": @[ listen ] };
		postJson(s, body, ^(const PostResult& r) {
			if (r.ok)
			{
				logMsg(@"Listen submitted OK!");
				flushCache();
			}
			else if (r.bad)
			{
				logMsg(@"Server responded with error code 400, meaning the submission was not accepted and cannot be retried because it was malformed.");
			}
			else
			{
				logStd(r.message);
				cacheListen(listen);
			}
		});
	}

	void verifyToken(void (^done)(bool, NSString*))
	{
		Settings s = settings();
		if (!isDefaultServer(s))
		{
			done(false, @"Token check is only available for the official ListenBrainz server.");
			return;
		}
		NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kValidateUrl]
			cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
		[req setValue:[NSString stringWithFormat:@"Token %s", s.token.c_str()] forHTTPHeaderField:@"Authorization"];
		[[[NSURLSession sharedSession] dataTaskWithRequest:req
			completionHandler:^(NSData* data, NSURLResponse*, NSError* error)
		{
			if (error)
			{
				done(false, [NSString stringWithFormat:@"Could not reach ListenBrainz: %@", error.localizedDescription]);
				return;
			}
			id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
			if ([json isKindOfClass:[NSDictionary class]])
			{
				NSDictionary* d = (NSDictionary*)json;
				id valid = d[@"valid"];
				if ([valid respondsToSelector:@selector(boolValue)] && [valid boolValue])
				{
					NSString* user = [d[@"user_name"] isKindOfClass:[NSString class]] ? d[@"user_name"] : @"(unknown)";
					done(true, [NSString stringWithFormat:@"Token valid. Submitting as \"%@\".", user]);
					return;
				}
				NSString* msg = [d[@"message"] isKindOfClass:[NSString class]] ? d[@"message"] : @"The token was not accepted.";
				done(false, [NSString stringWithFormat:@"ListenBrainz says: %@", msg]);
				return;
			}
			done(false, @"ListenBrainz sent an answer this component did not understand.");
		}] resume];
	}
}
