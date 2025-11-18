#import <Cocoa/Cocoa.h>
#import "license.h" // Ensure this file exists or use the mock implementation

#define BASE_BUNDLE_ID @"com.tencent.xinWeChat"
#define SRC @"/Applications/WeChat.app"

// --- UI Helper Categories ---
@interface NSTextField (ModernSetup)
+ (instancetype)labelWithString:(NSString *)str font:(NSFont *)font color:(NSColor *)color;
@end

@implementation NSTextField (ModernSetup)
+ (instancetype)labelWithString:(NSString *)str font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:str];
    label.font = font;
    label.textColor = color;
    return label;
}
@end

// --- AppDelegate Interface ---
@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (retain) NSWindow *window;
// UI Elements
@property (retain) NSTextField *statusLabel;
@property (retain) NSTextField *numField;
@property (retain) NSStepper *numStepper;
@property (retain) NSButton *createBtn;

// Registration UI
@property (retain) NSWindow *regWindow;
@property (retain) NSTextField *uniqueIdField;
@property (retain) NSTextView *licenseField;
@property (retain) NSButton *registerBtn;
@property (nonatomic, retain) NSButton *copyIdBtn;

// Logic methods
- (void)applicationDidFinishLaunching:(NSNotification *)notif;
- (BOOL)checkLicense;
- (NSString *)getStoredLicense;
- (void)saveLicense:(NSString *)license;
- (void)showRegisterWindow;
- (void)performCreate:(int)num;
@end

// --- Logic Functions ---
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

// Returns YES if successful, NO if failed or cancelled
BOOL create_copy(int num) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dst = [NSString stringWithFormat:@"/Applications/WeChat%d.app", num];
    NSString *bundleId = [NSString stringWithFormat:@"%@%d", BASE_BUNDLE_ID, num];
    NSString *displayName = [NSString stringWithFormat:@"WeChat%d", num];

    if (![fm fileExistsAtPath:SRC]) return NO;

    NSString *tempDir = [NSString stringWithFormat:@"%@/unlock-wechat-temp-%d", NSTemporaryDirectory(), rand()];
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *tempApp = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"WeChat%d.app", num]];
    if (![fm copyItemAtPath:SRC toPath:tempApp error:nil]) {
        [fm removeItemAtPath:tempDir error:nil];
        return NO;
    }

    NSString *plistPath = [tempApp stringByAppendingPathComponent:@"Contents/Info.plist"];
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!plist) { [fm removeItemAtPath:tempDir error:nil]; return NO; }
    
    NSMutableDictionary *mutPlist = [plist mutableCopy];
    [mutPlist setObject:bundleId forKey:@"CFBundleIdentifier"];
    [mutPlist setObject:displayName forKey:@"CFBundleName"];
    [mutPlist setObject:displayName forKey:@"CFBundleDisplayName"];
    BOOL success = [mutPlist writeToFile:plistPath atomically:YES];
    [mutPlist release];
    
    if (!success) { [fm removeItemAtPath:tempDir error:nil]; return NO; }

    NSString *scriptPath = [NSString stringWithFormat:@"%@/wechat_setup.sh", tempDir];
    NSString *user = NSUserName();
    
    // NOTE: Properly escaping the path for bash
    NSString *scriptContent = [NSString stringWithFormat:@"#!/bin/bash\n"
                               "mv '%@' '%@'\n"
                               "xattr -cr '%@'\n"
                               "/usr/bin/codesign --force --deep --sign - '%@'\n"
                               "chown -R %s '%@'\n",
                               tempApp, dst, dst, dst, [user UTF8String], dst];
    
    [scriptContent writeToFile:scriptPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm setAttributes:@{NSFilePosixPermissions: @(0755)} ofItemAtPath:scriptPath error:nil];

    NSString *escapedScriptPath = [scriptPath stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    NSString *command = [NSString stringWithFormat:@"/bin/bash '%@'", escapedScriptPath];
    
    // Execute with AppleScript to prompt for sudo
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
        [NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges", 
            [command stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]]];
    
    NSDictionary *errorDict = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&errorDict];
    [script release];
    
    // Cleanup temp directory
    [fm removeItemAtPath:tempDir error:nil];
    
    if (result == nil) {
        // Check if user cancelled (Error -128)
        NSNumber *errNum = [errorDict objectForKey:NSAppleScriptErrorNumber];
        if ([errNum intValue] == -128) {
            NSLog(@"User cancelled the operation.");
        } else {
            NSLog(@"AppleScript error: %@", errorDict);
        }
        return NO;
    }
    return YES;
}

// Returns YES only if ALL requested instances were created successfully
BOOL create_instances(int total_instances) {
    int target_copies = total_instances - 1;
    int current_count = get_copy_count();
    if (current_count >= target_copies) return YES; // Already have enough

    int to_create = target_copies - current_count;
    int next_num = 2;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (int i = 1; i <= to_create; i++) {
        // Find next available number
        while ([fm fileExistsAtPath:[NSString stringWithFormat:@"/Applications/WeChat%d.app", next_num]]) {
            next_num++;
        }
        
        BOOL result = create_copy(next_num);
        if (!result) {
            // If user cancelled or error occurred, stop the loop
            return NO;
        }
        next_num++;
    }
    return YES;
}

// --- AppDelegate Implementation ---

@implementation AppDelegate

- (NSButton *)copyIdBtn __attribute__((objc_method_family(none))) { return _copyIdBtn; }

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)applicationDidFinishLaunching:(NSNotification *)notif {
    // 1. Modern Window Setup
    NSRect frame = NSMakeRect(0, 0, 400, 280);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskFullSizeContentView
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.title = @""; 
    [self.window center];

    // 2. Visual Effect View
    NSVisualEffectView *effectView = [[NSVisualEffectView alloc] initWithFrame:frame];
    effectView.material = NSVisualEffectMaterialSidebar;
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateFollowsWindowActiveState;
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window setContentView:effectView];

    // 3. Build UI using Stack Views
    NSStackView *mainStack = [NSStackView new];
    mainStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainStack.spacing = 15;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [effectView addSubview:mainStack];

    // Constraints for Main Stack
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.centerXAnchor constraintEqualToAnchor:effectView.centerXAnchor],
        [mainStack.centerYAnchor constraintEqualToAnchor:effectView.centerYAnchor]
    ]];

    // -- App Icon / Header --
    NSImageView *iconView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"NSApplicationIcon"]];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [iconView.heightAnchor constraintEqualToConstant:64].active = YES;
    [iconView.widthAnchor constraintEqualToConstant:64].active = YES;
    [mainStack addArrangedSubview:iconView];
    
    NSTextField *titleLabel = [NSTextField labelWithString:@"Unlock WeChat" 
                                                     font:[NSFont systemFontOfSize:22 weight:NSFontWeightBold] 
                                                    color:[NSColor labelColor]];
    [mainStack addArrangedSubview:titleLabel];

    // -- Status Section --
    self.statusLabel = [NSTextField labelWithString:@"" font:[NSFont systemFontOfSize:14] color:[NSColor secondaryLabelColor]];
    [mainStack addArrangedSubview:self.statusLabel];
    [self updateStatus]; 

    // -- Spacer --
    NSView *spacer = [[NSView alloc] init];
    [mainStack addArrangedSubview:spacer];
    [spacer.heightAnchor constraintEqualToConstant:5].active = YES;
    [spacer release];

    // -- Control Row --
    NSStackView *controlStack = [NSStackView new];
    controlStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controlStack.spacing = 8;
    
    NSTextField *countLabel = [NSTextField labelWithString:@"Target Instances:" 
                                                     font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] 
                                                    color:[NSColor labelColor]];
    
    self.numField = [[NSTextField alloc] init];
    self.numField.stringValue = @"2";
    self.numField.alignment = NSTextAlignmentCenter;
    self.numField.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    [self.numField.widthAnchor constraintEqualToConstant:40].active = YES;
    [[self.numField cell] setPlaceholderString:@"2"];
    
    self.numStepper = [[NSStepper alloc] init];
    self.numStepper.intValue = 2;
    self.numStepper.minValue = 2;
    self.numStepper.maxValue = 20;
    self.numStepper.increment = 1;
    self.numStepper.valueWraps = NO;
    self.numStepper.target = self;
    self.numStepper.action = @selector(stepperAction:);
    
    [controlStack addArrangedSubview:countLabel];
    [controlStack addArrangedSubview:self.numField];
    [controlStack addArrangedSubview:self.numStepper];
    
    [mainStack addArrangedSubview:controlStack];

    // -- Action Button --
    self.createBtn = [NSButton buttonWithTitle:@"Create Instances" target:self action:@selector(createAction:)];
    self.createBtn.bezelStyle = NSBezelStyleRounded;
    self.createBtn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    self.createBtn.keyEquivalent = @"\r";
    [self.createBtn.widthAnchor constraintEqualToConstant:150].active = YES;
    
    [mainStack addArrangedSubview:self.createBtn];

    [self createMainMenu];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)updateStatus {
    int count = get_copy_count() + 1;
    NSString *text = [NSString stringWithFormat:@"Current Instances: %d", count];
    
    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] initWithString:text];
    NSRange numRange = [text rangeOfString:[NSString stringWithFormat:@"%d", count]];
    
    [attr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:14] range:NSMakeRange(0, text.length)];
    [attr addAttribute:NSForegroundColorAttributeName value:[NSColor secondaryLabelColor] range:NSMakeRange(0, text.length)];
    
    [attr addAttribute:NSForegroundColorAttributeName value:[NSColor systemGreenColor] range:numRange];
    [attr addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:14 weight:NSFontWeightBold] range:numRange];
    
    self.statusLabel.attributedStringValue = attr;
    [attr release];
}

- (void)stepperAction:(NSStepper *)sender {
    [self.numField setIntegerValue:[sender integerValue]];
}

- (void)checkAction:(id)sender {
    [self updateStatus];
}

// --- License Logic ---

- (NSString *)getStoredLicense {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefsPath = [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), bundleId];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
    return [dict objectForKey:@"licenseKey"];
}

- (void)saveLicense:(NSString *)license {
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSString *prefsPath = [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), bundleId];
    NSMutableDictionary *dict = [[NSDictionary dictionaryWithContentsOfFile:prefsPath] mutableCopy];
    if (!dict) dict = [NSMutableDictionary new];
    [dict setObject:license forKey:@"licenseKey"];
    [dict writeToFile:prefsPath atomically:YES];
}

- (BOOL)checkLicense {
    // Mock check - replace with real verification if needed
    return [self getStoredLicense] != nil;
}

// --- Actions ---

- (void)createAction:(NSButton *)sender {
    int num = [self.numField intValue];
    [self.numStepper setIntValue:num];

    if (num < 2 || num > 20) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Invalid Count";
        alert.informativeText = @"Total instances must be between 2 and 20.";
        [alert runModal];
        return;
    }

    if (![self checkLicense]) {
        [self showRegisterWindow];
        return;
    }

    [self performCreate:num];
}

- (void)performCreate:(int)num {
    self.createBtn.enabled = NO;
    self.createBtn.title = @"Processing...";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL success = create_instances(num);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateStatus];
            self.createBtn.enabled = YES;
            self.createBtn.title = @"Create Instances";
            
            if (success) {
                NSAlert *done = [[NSAlert alloc] init];
                done.messageText = @"Complete";
                done.informativeText = [NSString stringWithFormat:@"Successfully prepared %d instances.", num];
                [done runModal];
                [done release];
            } else {
                // Logic to handle cancellation or error (optional: show error alert)
                // We just don't show the Success message, which implies it was stopped.
            }
        });
    });
}

// --- Registration Window ---

- (void)showRegisterWindow {
    if (self.regWindow) {
        [self.regWindow makeKeyAndOrderFront:nil];
        return;
    }

    NSRect frame = NSMakeRect(0, 0, 380, 250);
    self.regWindow = [[NSWindow alloc] initWithContentRect:frame 
                                                 styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskFullSizeContentView
                                                   backing:NSBackingStoreBuffered defer:NO];
    self.regWindow.titlebarAppearsTransparent = YES;
    
    NSVisualEffectView *bg = [[NSVisualEffectView alloc] initWithFrame:frame];
    bg.material = NSVisualEffectMaterialPopover; 
    bg.state = NSVisualEffectStateActive;
    self.regWindow.contentView = bg;

    NSStackView *stack = [NSStackView new];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.spacing = 10;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:bg.topAnchor constant:30],
        [stack.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor]
    ]];

    NSTextField *title = [NSTextField labelWithString:@"Activate License" font:[NSFont boldSystemFontOfSize:16] color:[NSColor labelColor]];
    [stack addArrangedSubview:title];

    // Machine ID Section
    NSStackView *idStack = [NSStackView new];
    NSTextField *idLabel = [NSTextField labelWithString:@"Machine ID:" font:[NSFont systemFontOfSize:12] color:[NSColor secondaryLabelColor]];
    
    self.uniqueIdField = [NSTextField labelWithString:@"Fetching..."];
    self.uniqueIdField.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.uniqueIdField.selectable = YES;
    self.uniqueIdField.stringValue = @"AA-BB-CC-DD"; // Mock ID

    self.copyIdBtn = [NSButton buttonWithTitle:@"Copy" target:self action:@selector(copyIdAction:)];
    self.copyIdBtn.bezelStyle = NSBezelStyleInline;
    
    [idStack addArrangedSubview:idLabel];
    [idStack addArrangedSubview:self.uniqueIdField];
    [idStack addArrangedSubview:self.copyIdBtn];
    [stack addArrangedSubview:idStack];

    // License Input
    NSTextField *inputLabel = [NSTextField labelWithString:@"Enter License Key:" font:[NSFont systemFontOfSize:12] color:[NSColor labelColor]];
    [stack addArrangedSubview:inputLabel];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.borderType = NSBezelBorder;
    self.licenseField = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 340, 60)];
    scroll.documentView = self.licenseField;
    [scroll.heightAnchor constraintEqualToConstant:60].active = YES;
    [stack addArrangedSubview:scroll];

    // Buttons
    NSStackView *btnStack = [NSStackView new];
    btnStack.spacing = 10;
    NSButton *cancel = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(cancelAction:)];
    self.registerBtn = [NSButton buttonWithTitle:@"Activate" target:self action:@selector(registerAction:)];
    self.registerBtn.bezelStyle = NSBezelStyleRounded;
    self.registerBtn.keyEquivalent = @"\r";

    [btnStack addArrangedSubview:cancel];
    [btnStack addArrangedSubview:self.registerBtn];
    [stack addArrangedSubview:btnStack];

    [self.window beginSheet:self.regWindow completionHandler:^(NSModalResponse returnCode) {
        self.regWindow = nil;
    }];
}

- (void)registerAction:(NSButton *)sender {
    NSString *license = [[self.licenseField textStorage] string];
    license = [license stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (license.length > 0) {
        [self saveLicense:license];
        [self.window endSheet:self.regWindow];
        [self createAction:nil];
    } else {
        NSBeep();
    }
}

- (void)cancelAction:(NSButton *)sender {
    [self.window endSheet:self.regWindow];
}

- (void)copyIdAction:(NSButton *)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb writeObjects:@[self.uniqueIdField.stringValue]];
    sender.title = @"Copied!";
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.title = @"Copy";
    });
}

- (void)createMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];
    
    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    [NSApp setMainMenu:mainMenu];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        return NSApplicationMain(argc, argv);
    }
}