#import <Cocoa/Cocoa.h>

#define BASE_BUNDLE_ID @"com.tencent.xinWeChat"
#define SRC @"/Applications/WeChat.app"

// AppDelegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (retain) NSWindow *window;
@property (retain) NSTextField *statusLabel;
@property (retain) NSTextField *numField;
@property (retain) NSButton *checkBtn;
@property (retain) NSButton *createBtn;
- (void)applicationDidFinishLaunching:(NSNotification *)notif;
@end

// Ported functions
NSArray *scan_wechat_copies(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *copies = [NSMutableArray array];
    for (int i = 2; i <= 99; i++) {
        NSString *path = [NSString stringWithFormat:@"/Applications/WeChat%d.app", i];
        if ([fm fileExistsAtPath:path]) {
            [copies addObject:[NSNumber numberWithInt:i]];
        }
    }
    return copies;
}

int get_copy_count(void) {
    return (int)[scan_wechat_copies() count];
}

BOOL create_copy(int num) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dst = [NSString stringWithFormat:@"/Applications/WeChat%d.app", num];
    NSString *bundleId = [NSString stringWithFormat:@"%@%d", BASE_BUNDLE_ID, num];
    NSString *displayName = [NSString stringWithFormat:@"WeChat%d", num];

    if (![fm fileExistsAtPath:SRC]) return NO;

    // Create temp dir
    NSString *tempDir = [NSString stringWithFormat:@"%@/unlock-wechat-temp-%d", NSTemporaryDirectory(), rand()];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *tempApp = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"WeChat%d.app", num]];
    BOOL success = [fm copyItemAtPath:SRC toPath:tempApp error:nil];
    if (!success) {
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }

    // Modify plist
    NSString *plistPath = [tempApp stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) {
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }
    NSMutableDictionary *mutPlist = [plist mutableCopy];
    [mutPlist setObject:bundleId forKey:@"CFBundleIdentifier"];
    [mutPlist setObject:displayName forKey:@"CFBundleName"];
    [mutPlist setObject:displayName forKey:@"CFBundleDisplayName"];
    success = [mutPlist writeToFile:plistPath atomically:YES];
    [mutPlist release];
    if (!success) {
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }

    // Create script for privileged commands
    NSString *scriptPath = [NSString stringWithFormat:@"%@/wechat_setup.sh", tempDir];
    NSString *user = NSUserName();
    NSString *scriptContent = [NSString stringWithFormat:@"#!/bin/bash\n"
                               "mv '%@' '%@'\n"
                               "xattr -cr '%@'\n"
                               "/usr/bin/codesign --force --deep --sign - '%@'\n"
                               "chown -R %s '%@'\n",
                               tempApp, dst, dst, dst, [user UTF8String], dst];
    NSError *writeError;
    if (![scriptContent writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }

    // Make script executable
    NSDictionary *attrs = @{NSFilePosixPermissions: @(0755)};
    [fm setAttributes:attrs ofItemAtPath:scriptPath error:nil];

    // Execute script with admin privileges - need to properly escape and use bash
    NSString *escapedScriptPath = [scriptPath stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *command = [NSString stringWithFormat:@"/bin/bash '%@'", escapedScriptPath];
    
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
        [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", 
            [command stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
    
    NSDictionary *errorDict;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&errorDict];
    [script release];
    
    if (result == nil) {
        NSLog(@"AppleScript error: %@", errorDict);
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }

    // Cleanup temp
    [fm removeItemAtPath:tempDir error:nil];
    return YES;
}

void create_instances(int total_instances) {
    int target_copies = total_instances - 1;
    int current_count = get_copy_count();
    if (current_count >= target_copies) return;

    int to_create = target_copies - current_count;
    int next_num = 2;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (int i = 1; i <= to_create; i++) {
        while ([fm fileExistsAtPath:[NSString stringWithFormat:@"/Applications/WeChat%d.app", next_num]]) {
            next_num++;
        }
        create_copy(next_num);
        next_num++;
    }
}

@implementation AppDelegate

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notif {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 200, 350, 120) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    [self.window setTitle:@"UnLock WeChat"];
    [self.window center];

    NSView *view = [self.window contentView];

    int count = get_copy_count() + 1;
    NSString *statusText = [NSString stringWithFormat:@"You have %d WeChat instances.", count];
    NSRange range = [statusText rangeOfString:[NSString stringWithFormat:@"%d", count]];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:statusText];
    [attributed addAttribute:NSForegroundColorAttributeName value:[NSColor greenColor] range:range];
    [attributed addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:16] range:range];

    self.statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 75, 270, 25)];
    [self.statusLabel setEditable:NO];
    [self.statusLabel setBordered:NO];
    [self.statusLabel setDrawsBackground:NO];
    [self.statusLabel setAttributedStringValue:attributed];
    [attributed release];
    [view addSubview:self.statusLabel];

    NSTextField *numLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 170, 20)];
    [numLabel setEditable:NO];
    [numLabel setBordered:NO];
    [numLabel setDrawsBackground:NO];
    [numLabel setStringValue:@"Desired total instances:"];
    [view addSubview:numLabel];

    self.numField = [[NSTextField alloc] initWithFrame:NSMakeRect(180, 40, 50, 20)];
    [self.numField setStringValue:@"2"];
    [view addSubview:self.numField];

    self.checkBtn = [[NSButton alloc] initWithFrame:NSMakeRect(250, 76, 75, 24)];
    [self.checkBtn setTitle:@"Check"];
    [self.checkBtn setTarget:self];
    [self.checkBtn setAction:@selector(checkAction:)];
    [view addSubview:self.checkBtn];

    self.createBtn = [[NSButton alloc] initWithFrame:NSMakeRect(250, 38, 75, 24)];
    [self.createBtn setTitle:@"Create"];
    [self.createBtn setTarget:self];
    [self.createBtn setAction:@selector(createAction:)];
    [view addSubview:self.createBtn];

    // Note: Tag abused for reference, but for simplicity, global vars or better class vars.

    // Actually, use properties in AppDelegate.

    // Since small, hardcode.

    [self.window makeKeyAndOrderFront:nil];
}

- (void)checkAction:(NSButton *)sender {
    int count = get_copy_count() + 1;
    NSString *statusText = [NSString stringWithFormat:@"You have %d WeChat instances.", count];
    NSRange range = [statusText rangeOfString:[NSString stringWithFormat:@"%d", count]];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:statusText];
    [attributed addAttribute:NSForegroundColorAttributeName value:[NSColor greenColor] range:range];
    [attributed addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:16] range:range];
    [self.statusLabel setAttributedStringValue:attributed];
    [attributed release];
}

- (void)createAction:(NSButton *)sender {
    int num = [[self.numField stringValue] intValue];
    if (num < 2 || num > 20) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error"];
        [alert setInformativeText:@"Total instances must be between 2 and 20."];
        NSImage *icon = [NSImage imageNamed:@"icon"];
        if (icon) [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    [self.createBtn setEnabled:NO];
    [self.createBtn setTitle:@"Creating..."];

    create_instances(num);
    int count = get_copy_count() + 1;
    NSString *statusText = [NSString stringWithFormat:@"You have %d WeChat instances.", count];
    NSRange range = [statusText rangeOfString:[NSString stringWithFormat:@"%d", count]];
    NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:statusText];
    [attributed addAttribute:NSForegroundColorAttributeName value:[NSColor greenColor] range:range];
    [attributed addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:16] range:range];
    [self.statusLabel setAttributedStringValue:attributed];
    [attributed release];

    [self.createBtn setEnabled:YES];
    [self.createBtn setTitle:@"Create"];
}

@end

int main(int argc, const char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [app setDelegate:delegate];

    [pool release];
    return NSApplicationMain(argc, argv);
}
