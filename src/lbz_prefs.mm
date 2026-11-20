// Preferences page (Settings > Tools > ListenBrainz 2), plain Cocoa.
#import <Cocoa/Cocoa.h>
#include <foobar2000/SDK/foobar2000.h>
#include <foobar2000/SDK/commonObjects-Apple.h>
#import "lbz_core.h"

static NSString* LBZTrim(NSString* s)
{
	return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@interface LBZ2PreferencesController : NSViewController <NSTextFieldDelegate>
@property(nonatomic, strong) NSTextField* tokenField;
@property(nonatomic, strong) NSTextField* urlField;
@property(nonatomic, strong) NSTextField* statusLabel;
@property(nonatomic, strong) NSButton* enabledCheck;
@property(nonatomic, strong) NSButton* artistCheck;
@property(nonatomic, strong) NSButton* libraryCheck;
@property(nonatomic, strong) NSButton* clientCheck;
@end

@implementation LBZ2PreferencesController

- (NSTextField*)addLabel:(NSString*)text y:(CGFloat)y
{
	NSTextField* l = [NSTextField labelWithString:text];
	l.frame = NSMakeRect(20, y, 520, 18);
	[self.view addSubview:l];
	return l;
}

- (NSTextField*)addFieldWithValue:(NSString*)value placeholder:(NSString*)ph y:(CGFloat)y
{
	NSTextField* f = [[NSTextField alloc] initWithFrame:NSMakeRect(20, y, 520, 24)];
	f.stringValue = value ?: @"";
	f.placeholderString = ph;
	f.delegate = self;
	[self.view addSubview:f];
	return f;
}

- (NSButton*)addCheck:(NSString*)title on:(bool)on y:(CGFloat)y
{
	NSButton* b = [NSButton checkboxWithTitle:title target:self action:@selector(settingChanged:)];
	b.frame = NSMakeRect(20, y, 520, 20);
	b.state = on ? NSControlStateValueOn : NSControlStateValueOff;
	[self.view addSubview:b];
	return b;
}

- (void)loadView
{
	self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 560, 300)];
	const lbz::Settings s = lbz::settings();

	[self addLabel:@"Submit the music you listen to ListenBrainz (or a compatible server)." y:268];
	[self addLabel:@"User token (find it at listenbrainz.org/profile):" y:240];
	self.tokenField = [self addFieldWithValue:[NSString stringWithUTF8String:s.token.c_str()]
		placeholder:@"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" y:212];
	[self addLabel:@"API URL (leave empty for the official ListenBrainz server):" y:184];
	self.urlField = [self addFieldWithValue:[NSString stringWithUTF8String:s.apiUrl.c_str()]
		placeholder:lbz::kDefaultApiUrl y:156];

	self.enabledCheck = [self addCheck:@"Enable submission" on:s.enabled y:122];
	self.artistCheck = [self addCheck:@"Submit only the first artist when a track has several" on:s.artistFirst y:98];
	self.libraryCheck = [self addCheck:@"Only submit tracks that are in the Media Library" on:s.libraryOnly y:74];
	self.clientCheck = [self addCheck:@"Send player and component version with each listen" on:s.clientDetails y:50];

	NSButton* test = [NSButton buttonWithTitle:@"Test token" target:self action:@selector(testToken:)];
	test.frame = NSMakeRect(20, 10, 110, 30);
	[self.view addSubview:test];

	self.statusLabel = [NSTextField labelWithString:@""];
	self.statusLabel.frame = NSMakeRect(140, 15, 400, 18);
	[self.view addSubview:self.statusLabel];
}

- (void)settingChanged:(id)sender
{
	lbz::Settings n;
	n.token = [LBZTrim(self.tokenField.stringValue) UTF8String];
	n.apiUrl = [LBZTrim(self.urlField.stringValue) UTF8String];
	n.enabled = self.enabledCheck.state == NSControlStateValueOn;
	n.artistFirst = self.artistCheck.state == NSControlStateValueOn;
	n.libraryOnly = self.libraryCheck.state == NSControlStateValueOn;
	n.clientDetails = self.clientCheck.state == NSControlStateValueOn;
	lbz::saveSettings(n);
	if (lbz::isValidToken(n)) lbz::flushCache();
}

- (void)controlTextDidChange:(NSNotification*)note
{
	[self settingChanged:nil];
}

- (void)testToken:(id)sender
{
	[self settingChanged:nil];
	self.statusLabel.stringValue = @"Checking...";
	__weak LBZ2PreferencesController* weakSelf = self;
	lbz::verifyToken(^(bool valid, NSString* message) {
		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.statusLabel.stringValue = message ?: @"";
		});
	});
}

@end

namespace lbz
{
	static const GUID guid_prefs_page = { 0x10977af1, 0xd46d, 0x413c, { 0xa1, 0x6a, 0x86, 0x64, 0x58, 0x53, 0xff, 0x13 } };

	class lbz_preferences_page : public preferences_page_v2
	{
	public:
		service_ptr instantiate() override
		{
			return fb2k::wrapNSObject([LBZ2PreferencesController new]);
		}

		const char* get_name() override { return "ListenBrainz 2"; }
		GUID get_guid() override { return guid_prefs_page; }
		GUID get_parent_guid() override { return preferences_page::guid_tools; }
	};

	FB2K_SERVICE_FACTORY(lbz_preferences_page);
}
