#import <Cocoa/Cocoa.h>
#import "license.h"

#define BASE_BUNDLE_ID @"com.tencent.xinWeChat"
#define SRC @"/Applications/WeChat.app"

// AppDelegate
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (retain) NSWindow *window;
@property (retain) NSTextField *statusLabel;
@property (retain) NSTextField *numField;
@property (retain) NSButton *checkBtn;
@property (retain) NSButton *createBtn;
@property (retain) NSWindow *regWindow;
@property (retain) NSTextField *uniqueIdField;
@property (retain) NSTextView *licenseField;
@property (retain) NSButton *registerBtn;
@property (nonatomic, retain) NSButton *copyIdBtn;
- (void)applicationDidFinishLaunching:(NSNotification *)notif;
- (BOOL)checkLicense;
- (NSString *)getStoredLicense;
- (void)saveLicense:(NSString *)license;
- (void)showRegisterWindow;
- (void)performCreate:(int)num;
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

- (NSButton *)copyIdBtn __attribute__((objc_method_family(none))) {

    return _copyIdBtn;

}

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

    self.createBtn = [[NSButton alloc] initWithFrame:NSMakeRect(250, 37, 75, 24)];
    [self.createBtn setTitle:@"Create"];
    [self.createBtn setTarget:self];
    [self.createBtn setAction:@selector(createAction:)];
    [view addSubview:self.createBtn];

    // Note: Tag abused for reference, but for simplicity, global vars or better class vars.

    // Actually, use properties in AppDelegate.

    // Since small, hardcode.

    // Create standard main menu for macOS app
    [self createMainMenu];

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

- (NSString *)getStoredLicense {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefsPath = [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), bundleId];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    return [dict objectForKey:@"licenseKey"];
}

- (void)saveLicense:(NSString *)license {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefsPath = [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), bundleId];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    if (!existing) existing = @{};
    NSMutableDictionary *dict = [existing mutableCopy];
    [dict setObject:license forKey:@"licenseKey"];
    [dict writeToFile:prefsPath atomically:YES];
}

- (BOOL)checkLicense {
    NSString *storedLicense = [self getStoredLicense];
    if (!storedLicense) return NO;

    unsigned char token[4];
    if (!GetMachineToken(token)) return NO;

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *publicKeyPath = [bundle pathForResource:@"public" ofType:@"key"];
    if (!publicKeyPath) return NO;

    return VerifyLicense([storedLicense UTF8String], token, publicKeyPath);
}

- (void)createAction:(NSButton *)sender {
    int num = [[self.numField stringValue] intValue];
    if (num < 2 || num > 20) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error"];
        [alert setInformativeText:@"Total instances must be between 2 and 20."];
        NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"icon" ofType:@"icns"]];
        [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    if (![self checkLicense]) {
        [self showRegisterWindow];
        return;
    }

    [self performCreate:num];
}

- (void)performCreate:(int)num {
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

- (void)showRegisterWindow {
    if (self.regWindow) {
        [self.regWindow makeKeyAndOrderFront:nil];
        return;
    }

    self.regWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 350, 220) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    [self.regWindow setTitle:@"Register"];

    NSView *view = [self.regWindow contentView];

    NSTextField *idLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 170, 50, 25)];
    [idLabel setEditable:NO];
    [idLabel setBordered:NO];
    [idLabel setDrawsBackground:NO];
    [idLabel setStringValue:@"ID:"];
    [view addSubview:idLabel];

    self.uniqueIdField = [[NSTextField alloc] initWithFrame:NSMakeRect(60, 170, 220, 25)];
    [self.uniqueIdField setEditable:NO];
    [self.uniqueIdField setSelectable:YES];
    [self.uniqueIdField setBordered:NO];
    [self.uniqueIdField setDrawsBackground:NO];

    unsigned char token[4];
    if (GetMachineToken(token)) {
        NSString *idStr = [NSString stringWithFormat:@"%02X-%02X-%02X-%02X", token[0], token[1], token[2], token[3]];
        [self.uniqueIdField setStringValue:idStr];
    } else {
        [self.uniqueIdField setStringValue:@"Error"];
    }
    [view addSubview:self.uniqueIdField];

    self.copyIdBtn = [[NSButton alloc] initWithFrame:NSMakeRect(150, 172, 85, 25)];
    [self.copyIdBtn setTitle:@"Copy"];
    [self.copyIdBtn setTarget:self];
    [self.copyIdBtn setAction:@selector(copyIdAction:)];
    [view addSubview:self.copyIdBtn];

    NSTextField *keyLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 140, 100, 25)];
    [keyLabel setEditable:NO];
    [keyLabel setBordered:NO];
    [keyLabel setDrawsBackground:NO];
    [keyLabel setStringValue:@"License Key:"];
    [view addSubview:keyLabel];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 45, 330, 90)];
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 330, 90)];
    [scrollView setDocumentView:textView];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setHasHorizontalScroller:NO];
    [scrollView setBorderType:NSBezelBorder];
    [view addSubview:scrollView];

    self.licenseField = textView;

    self.registerBtn = [[NSButton alloc] initWithFrame:NSMakeRect(195, 10, 80, 25)];
    [self.registerBtn setTitle:@"Register"];
    [self.registerBtn setTarget:self];
    [self.registerBtn setAction:@selector(registerAction:)];
    [view addSubview:self.registerBtn];

    NSButton *cancelBtn = [[NSButton alloc] initWithFrame:NSMakeRect(95, 10, 80, 25)];
    [cancelBtn setTitle:@"Cancel"];
    [cancelBtn setTarget:self];
    [cancelBtn setAction:@selector(cancelAction:)];
    [view addSubview:cancelBtn];

    [self.regWindow makeFirstResponder:self.licenseField];

    [self.window beginSheet:self.regWindow completionHandler:^(NSModalResponse returnCode) {
        self.regWindow = nil;
        self.uniqueIdField = nil;
        self.licenseField = nil;
        self.registerBtn = nil;
        self.copyIdBtn = nil;
        [self.regWindow orderOut:nil];
    }];
}

- (void)registerAction:(NSButton *)sender {
    NSString *license = [[self.licenseField textStorage] string];
    license = [license stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"icon" ofType:@"icns"]];

    if ([license length] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error"];
        [alert setInformativeText:@"Please enter a license key."];
        [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.regWindow completionHandler:nil];
        return;
    }

    unsigned char token[4];
    if (!GetMachineToken(token)) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error"];
        [alert setInformativeText:@"Unable to get machine ID."];
        [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.regWindow completionHandler:nil];
        return;
    }

    NSBundle *bundle = [NSBundle mainBundle];
    NSString *publicKeyPath = [bundle pathForResource:@"public" ofType:@"key"];
    if (!publicKeyPath) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Error"];
        [alert setInformativeText:@"Public key not found."];
        [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.regWindow completionHandler:nil];
        return;
    }

    if (VerifyLicense([license UTF8String], token, publicKeyPath)) {
        [self saveLicense:license];
        [self.window endSheet:self.regWindow];
        // Proceed with create
        int num = [[self.numField stringValue] intValue];
        [self performCreate:num];
    } else {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"Invalid License"];
        [alert setInformativeText:@"The license key is invalid or does not match this machine."];
        [alert setIcon:icon];
        [alert beginSheetModalForWindow:self.regWindow completionHandler:nil];
    }
}

- (void)cancelAction:(NSButton *)sender {
    [self.window endSheet:self.regWindow];
}

- (void)copyIdAction:(NSButton *)sender {
    [self.copyIdBtn setTitle:@"Copied✓"];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[self.uniqueIdField.stringValue]];
}

- (void)createMainMenu {
    // Create Application menu
    NSString *appName = [[NSProcessInfo processInfo] processName];
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    // Application menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle:appName action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:appName];
    [appMenuItem setSubmenu:appMenu];

    // About menu item
    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"About %@", appName] action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [aboutItem setTarget:NSApp];
    [appMenu addItem:aboutItem];

    // Separator
    [appMenu addItem:[NSMenuItem separatorItem]];

    // Services menu
    NSMenuItem *servicesItem = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    [servicesItem setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:servicesItem];

    // Separator
    [appMenu addItem:[NSMenuItem separatorItem]];

    // Hide menu item
    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Hide %@", appName] action:@selector(hide:) keyEquivalent:@"h"];
    [hideItem setTarget:NSApp];
    [appMenu addItem:hideItem];

    // Hide Others menu item
    NSMenuItem *hideOthersItem = [[NSMenuItem alloc] initWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [hideOthersItem setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];
    [hideOthersItem setTarget:NSApp];
    [appMenu addItem:hideOthersItem];

    // Show All menu item
    NSMenuItem *showAllItem = [[NSMenuItem alloc] initWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [showAllItem setTarget:NSApp];
    [appMenu addItem:showAllItem];

    // Separator
    [appMenu addItem:[NSMenuItem separatorItem]];

    // Quit menu item
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Quit %@", appName] action:@selector(terminate:) keyEquivalent:@"q"];
    [quitItem setTarget:NSApp];
    [appMenu addItem:quitItem];

    [mainMenu addItem:appMenuItem];

    // Edit menu
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenuItem setSubmenu:editMenu];

    // Undo
    NSMenuItem *undoItem = [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [undoItem setTarget:nil]; // nil means first responder
    [editMenu addItem:undoItem];

    // Redo
    NSMenuItem *redoItem = [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [redoItem setTarget:nil];
    [editMenu addItem:redoItem];

    // Separator
    [editMenu addItem:[NSMenuItem separatorItem]];

    // Cut
    NSMenuItem *cutItem = [[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [cutItem setTarget:nil];
    [editMenu addItem:cutItem];

    // Copy
    NSMenuItem *copyItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [copyItem setTarget:nil];
    [editMenu addItem:copyItem];

    // Paste
    NSMenuItem *pasteItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [pasteItem setTarget:nil];
    [editMenu addItem:pasteItem];

    // Select All
    NSMenuItem *selectAllItem = [[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [selectAllItem setTarget:nil];
    [editMenu addItem:selectAllItem];

    [mainMenu addItem:editMenuItem];

    // Window menu
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenuItem setSubmenu:windowMenu];

    // Minimize
    NSMenuItem *minimizeItem = [[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [minimizeItem setTarget:nil];
    [windowMenu addItem:minimizeItem];

    // Zoom
    NSMenuItem *zoomItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [zoomItem setTarget:nil];
    [windowMenu addItem:zoomItem];

    // Separator
    [windowMenu addItem:[NSMenuItem separatorItem]];

    // Bring All to Front
    NSMenuItem *bringAllToFrontItem = [[NSMenuItem alloc] initWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    [bringAllToFrontItem setTarget:nil];
    [windowMenu addItem:bringAllToFrontItem];

    [mainMenu addItem:windowMenuItem];

    [NSApp setMainMenu:mainMenu];
    [NSApp setWindowsMenu:windowMenu];
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
