//
//  GeneralPreferencesViewController.m
//  Vienna
//
//  Created by Joshua Pore on 22/11/2014.
//  Copyright (c) 2014 uk.co.opencommunity. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "Constants.h"
#import "GeneralPreferencesViewController.h"
#import "PopUpButtonExtensions.h"
#import "Preferences.h"

@interface GeneralPreferencesViewController ()

-(void)initializePreferences;
// -(void)selectUserDefaultFont:(NSString *)name size:(int)size control:(NSPopUpButton *)control sizeControl:(NSComboBox *)sizeControl;
-(void)setDefaultLinksHandler:(NSURL *)pathToNewHandler;
// -(void)controlTextDidEndEditing:(NSNotification *)notification;
-(void)refreshLinkHandler;
-(IBAction)handleLinkSelector:(id)sender;
-(void)updateDownloadsPopUp:(NSString *)downloadFolderPath;

@end

@implementation GeneralPreferencesViewController


- (instancetype)init {
	if ((self = [super initWithNibName:@"GeneralPreferencesView" bundle:nil]) != nil)
	{
        // Set up to be notified if preferences change outside this window
        NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(handleReloadPreferences:) name:@"MA_Notify_CheckFrequencyChange" object:nil];
        [nc addObserver:self selector:@selector(handleReloadPreferences:) name:@"MA_Notify_PreferenceChange" object:nil];
        appToPathMap = [[NSMutableDictionary alloc] init];
	}
	return self;
}


- (void)viewWillAppear {
    if([NSViewController instancesRespondToSelector:@selector(viewWillAppear)]) {
        [super viewWillAppear];
    }
    
    [self initializePreferences];
    
}


#pragma mark - MASPreferencesViewController

- (NSString *)viewIdentifier {
    return @"GeneralPreferences";
}

- (NSImage *)toolbarItemImage
{
    return [NSImage imageNamed:NSImageNamePreferencesGeneral];
}

- (NSString *)toolbarItemLabel
{
    return NSLocalizedString(@"General", @"Toolbar item name for the General preference pane");
}

#pragma mark - Vienna Preferences handling

/* handleReloadPreferences
 * This gets called when MA_Notify_PreferencesUpdated is broadcast. Just update the controls values.
 */
-(void)handleReloadPreferences:(NSNotification *)nc
{
    [self initializePreferences];
}

/* initializePreferences
 * Set the preference settings from the user defaults.
 */
-(void)initializePreferences
{
    Preferences * prefs = [Preferences standardPreferences];
    
    // Set the check frequency
    [checkFrequency selectItemAtIndex:[checkFrequency indexOfItemWithTag:prefs.refreshFrequency]];
    
    // Set check for updates when starting
    checkForUpdates.state = prefs.checkForNewOnStartup ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Set search for latest Beta versions when checking for updates
    alwaysAcceptBetas.state = prefs.alwaysAcceptBetas ? NSControlStateValueOn : NSControlStateValueOff;

    // Set check for new articles when starting
    checkOnStartUp.state = prefs.refreshOnStartup ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Set range of auto-expire values
    [expireDuration removeAllItems];
    [expireDuration insertItemWithTag:NSLocalizedString(@"Never", nil) tag:0 atIndex:0];
    [expireDuration insertItemWithTag:NSLocalizedString(@"After a Day", nil) tag:1 atIndex:1];
    [expireDuration insertItemWithTag:NSLocalizedString(@"After 2 Days", nil) tag:2 atIndex:2];
    [expireDuration insertItemWithTag:NSLocalizedString(@"After a Week", nil) tag:7 atIndex:3];
    [expireDuration insertItemWithTag:NSLocalizedString(@"After 2 Weeks", nil) tag:14 atIndex:4];
    [expireDuration insertItemWithTag:NSLocalizedString(@"After a Month", nil) tag:1000 atIndex:5];
    
    // Set auto-expire duration
    [expireDuration selectItemAtIndex:[expireDuration indexOfItemWithTag:prefs.autoExpireDuration]];
    
    // Set download folder
    [self updateDownloadsPopUp:prefs.downloadFolder];
    
    // Set whether the application is shown in the menu bar
    showAppInMenuBar.state = prefs.showAppInStatusBar ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Set whether links are opened in the background
    openLinksInBackground.state = prefs.openLinksInBackground ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Set whether links are opened in the external browser
    openLinksInExternalBrowser.state = prefs.openLinksInVienna ? NSControlStateValueOff : NSControlStateValueOn;
    
    // Set mark read behaviour
    markReadAfterNext.state = prefs.markReadInterval == 0 ? NSControlStateValueOn : NSControlStateValueOff;
    markReadAfterDelay.state = prefs.markReadInterval != 0 ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Show new articles notification options
    newArticlesNotificationBadgeButton.state = ((prefs.newArticlesNotification & MANewArticlesNotificationBadge) !=0) ? NSControlStateValueOn : NSControlStateValueOff;
    newArticlesNotificationBounceButton.state = ((prefs.newArticlesNotification & MANewArticlesNotificationBounce) !=0) ? NSControlStateValueOn : NSControlStateValueOff;
    
    // Set whether updated articles are considered as new
    markUpdatedAsNew.state = prefs.markUpdatedAsNew ? NSControlStateValueOn : NSControlStateValueOff;
    
    [self refreshLinkHandler];
}

/* refreshLinkHandler
 * Populate the drop down list of registered handlers for the feed:// URL
 * using launch services.
 */
-(void)refreshLinkHandler
{
    NSBundle * appBundle = [NSBundle mainBundle];
    NSString * ourAppName = [[NSFileManager defaultManager] displayNameAtPath:appBundle.bundlePath];
    BOOL onTheList = NO;
    NSURL * testURL = [NSURL URLWithString:@"feed://www.test.com"];
    NSString * registeredAppURL = nil;
    
    // Clear all existing items
    [linksHandler removeAllItems];
    
    // Add the current registered link handler to the start of the list as Safari does. If
    // there's no current registered handler, default to ourself.
    CFStringRef defaultBundleIdentifier = LSCopyDefaultHandlerForURLScheme((__bridge CFStringRef)@"feed");
    if (defaultBundleIdentifier != NULL)
    {
        registeredAppURL = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:(__bridge NSString *)defaultBundleIdentifier].path;
        CFRelease(defaultBundleIdentifier);
    }
    else
    {
        registeredAppURL = appBundle.executablePath;
        onTheList = YES;
    }
    
    NSString * regAppName = [[NSFileManager defaultManager] displayNameAtPath:registeredAppURL];
    // Maintain a table to map from the short name to the file URL for when
    // the user changes selection and we later need the file URL to register
    // the new selection.
    if (regAppName != nil) {
        [linksHandler addItemWithTitle:regAppName image:[[NSWorkspace sharedWorkspace] iconForFile:registeredAppURL]];
        [linksHandler addSeparator];
        [appToPathMap setValue:registeredAppURL forKey:regAppName];
    }

    // Next, add the list of all registered link handlers under the /Applications folder
    // except for the registered application.
    CFArrayRef cfArrayOfApps = LSCopyApplicationURLsForURL((__bridge CFURLRef)testURL, kLSRolesAll);
    if (cfArrayOfApps != nil)
    {
        CFIndex count = CFArrayGetCount(cfArrayOfApps);
        NSInteger index;
        
        for (index = 0; index < count; ++index)
        {
            NSURL * appURL = (NSURL *)CFArrayGetValueAtIndex(cfArrayOfApps, index);
            if (appURL.fileURL && [appURL.path hasPrefix:@"/Applications/"])
            {
                NSString * appName = [[NSFileManager defaultManager] displayNameAtPath:appURL.path];
                if ([appName isEqualToString:ourAppName])
                    onTheList = YES;
                if (appName != nil && ![appName isEqualToString:regAppName])
                    [linksHandler addItemWithTitle:appName image:[[NSWorkspace sharedWorkspace] iconForFile:appURL.path]];
                
                [appToPathMap setValue:appURL forKey:appName];
            }
        }
        CFRelease(cfArrayOfApps);
    }
    
    // Were we on the list? If not, add ourselves
    // complete with our icon.
    if (!onTheList)
    {
        [linksHandler addItemWithTitle:ourAppName image:[[NSWorkspace sharedWorkspace] iconForFile:appBundle.bundlePath]];
        
        NSURL * fileURL = [[NSURL alloc] initFileURLWithPath:appBundle.bundlePath];
        [appToPathMap setValue:fileURL forKey:ourAppName];
    }
    
    // Add a Select command so the user can manually pick a registered
    // application.
    [linksHandler addSeparator];
    [linksHandler addItemWithTag:NSLocalizedString(@"Select…", nil) tag:-1];
    
    // Select the registered item
    [linksHandler selectItemAtIndex:0];
}

/* changeExpireDuration
 * Handle the change to the auto-expire duration.
 */
-(IBAction)changeExpireDuration:(id)sender
{
    NSMenuItem * selectedItem = expireDuration.selectedItem;
    if (selectedItem != nil)
        [Preferences standardPreferences].autoExpireDuration = selectedItem.tag;
}

/* changeOpenLinksInBackground
 * Sets whether Vienna opens new links in the background in the active web
 * browser.
 */
-(IBAction)changeOpenLinksInBackground:(id)sender
{
    [Preferences standardPreferences].openLinksInBackground = [sender state] == NSControlStateValueOn;
}

/* changeShowAppInMenuBar
 * Sets whether or not the application icon is shown in the menu bar.
 */
-(IBAction)changeShowAppInMenuBar:(id)sender
{
    [Preferences standardPreferences].showAppInStatusBar = [sender state] == NSControlStateValueOn;
}

/* changeMarkUpdatedAsNew
 * Sets whether Vienna considers updated articles
 * as new ones.
 */
-(IBAction)changeMarkUpdatedAsNew:(id)sender
{
    [Preferences standardPreferences].markUpdatedAsNew = [sender state] == NSControlStateValueOn;
}

/* changeOpenLinksInExternalBrowser
 * Sets whether Vienna opens new links in the browser view or in
 * the user's current default browser application.
 */
-(IBAction)changeOpenLinksInExternalBrowser:(id)sender
{
    [Preferences standardPreferences].openLinksInVienna = [sender state] == NSControlStateValueOff;
}

/* changeDownloadFolder
 * Bring up the folder browser to pick a new download folder.
 */
-(IBAction)changeDownloadFolder:(id)sender
{
    NSOpenPanel * openPanel = [NSOpenPanel openPanel];
    NSWindow * prefPaneWindow = downloadFolder.window;
    
    [openPanel setCanChooseDirectories:YES];
    [openPanel setCanCreateDirectories:YES];
    [openPanel setCanChooseFiles:NO];
    openPanel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSDownloadsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    [openPanel beginSheetModalForWindow:prefPaneWindow completionHandler:^(NSInteger returnCode) {
        // Force the focus back to the main preferences pane
        [openPanel orderOut:self];
        [prefPaneWindow makeKeyAndOrderFront:prefPaneWindow];
        
        if (returnCode == NSModalResponseOK)
        {
            NSString * downloadFolderPath = openPanel.directoryURL.path;
            [Preferences standardPreferences].downloadFolder = downloadFolderPath;
            [self updateDownloadsPopUp:downloadFolderPath];
        }
        
        if (returnCode == NSModalResponseCancel)
            [self->downloadFolder selectItemAtIndex:0];
    }];
}

/* updateDownloadsPopUp
 * Update the Downloads folder popup with the specified download folder path and image.
 */
-(void)updateDownloadsPopUp:(NSString *)downloadFolderPath
{
    NSMenuItem * downloadPathItem = [downloadFolder itemAtIndex:0];
    NSImage * pathImage = [[NSWorkspace sharedWorkspace] iconForFile:downloadFolderPath];
    
    pathImage.size = NSMakeSize(16, 16);
    
    downloadPathItem.title = [[NSFileManager defaultManager] displayNameAtPath:downloadFolderPath];
    downloadPathItem.image = pathImage;
    downloadPathItem.state = NSControlStateValueOff;
    
    [downloadFolder selectItemAtIndex:0];
}

/* changeCheckForUpdates
 * Set whether Vienna checks for updates when it starts.
 */
-(IBAction)changeCheckForUpdates:(id)sender
{
    [Preferences standardPreferences].checkForNewOnStartup = [sender state] == NSControlStateValueOn;
}

/* changeCheckOnStartUp
 * Set whether Vienna checks for new articles when it starts.
 */
-(IBAction)changeCheckOnStartUp:(id)sender
{
    [Preferences standardPreferences].refreshOnStartup = [sender state] == NSControlStateValueOn;
}

/* selectDefaultLinksHandler
 * The user picked something from the list of handlers.
 */
-(IBAction)selectDefaultLinksHandler:(id)sender
{
    NSMenuItem * selectedItem = linksHandler.selectedItem;
    if (selectedItem != nil)
    {
        if (selectedItem.tag == -1)
        {
            [self handleLinkSelector:self];
            return;
        }
    }
    [self setDefaultLinksHandler:[appToPathMap valueForKey:selectedItem.title]];
    [self refreshLinkHandler];
}

/* handleLinkSelector
 * Handle the 'Select...' command on the popup list of registered applications. Display the
 * file browser in the Applications folder and use that to add a new application to the
 * list.
 */
-(IBAction)handleLinkSelector:(id)sender
{
    NSOpenPanel * panel = [NSOpenPanel openPanel];
    NSWindow * prefPaneWindow = linksHandler.window;
    
    panel.directoryURL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationDirectory inDomain:NSLocalDomainMask appropriateForURL:nil create:NO error:nil];
    panel.allowedFileTypes = @[NSFileTypeForHFSTypeCode('APPL')];
    [panel beginSheetModalForWindow:prefPaneWindow completionHandler:^(NSInteger returnCode) {
        [panel orderOut:self];
        NSWindow * prefPaneWindow = self->linksHandler.window;
        [prefPaneWindow makeKeyAndOrderFront:self];
        
        if (returnCode == NSModalResponseOK)
            [self setDefaultLinksHandler:panel.URL];
        [self refreshLinkHandler];
    }];
}

/* setDefaultLinksHandler
 * Set the default handler for feed links via Launch Services
 */
-(void)setDefaultLinksHandler:(NSURL *)fileURLToNewHandler
{
    NSBundle * appBundle = [NSBundle bundleWithURL:fileURLToNewHandler];
    NSDictionary * fileAttributes = appBundle.infoDictionary;
    CFStringRef bundleIdentifier = (__bridge CFStringRef)fileAttributes[@"CFBundleIdentifier"];
    CFStringRef scheme = (__bridge CFStringRef)@"feed";
    LSSetDefaultHandlerForURLScheme(scheme, bundleIdentifier);
}

/* changeCheckFrequency
 * The user changed the connect frequency drop down so save the new value and then
 * tell the main app that it changed.
 */
-(IBAction)changeCheckFrequency:(id)sender
{
    NSInteger newFrequency = checkFrequency.selectedItem.tag;
    [Preferences standardPreferences].refreshFrequency = newFrequency;
}

/* changeNewArticlesNotificationBadge
 * Change if we display badge when new articles are announced.
 */
-(IBAction)changeNewArticlesNotificationBadge:(id)sender
{
    Preferences * prefs = [Preferences standardPreferences];
    NSInteger currentNotificationValue = prefs.newArticlesNotification;
    if ([sender state] == NSControlStateValueOn)
    {
        prefs.newArticlesNotification = currentNotificationValue | MANewArticlesNotificationBadge;
    }
    else
    {
        prefs.newArticlesNotification = currentNotificationValue & ~MANewArticlesNotificationBadge;
    }
}

/* changeNewArticlesNotificationBounce
 * Change if we require user attention (by bouncing the Dock icon) when new articles are announced.
 */
-(IBAction)changeNewArticlesNotificationBounce:(id)sender
{
    Preferences * prefs = [Preferences standardPreferences];
    NSInteger currentNotificationValue = prefs.newArticlesNotification;
    if ([sender state] == NSControlStateValueOn)
    {
        prefs.newArticlesNotification = currentNotificationValue | MANewArticlesNotificationBounce;
    }
    else
    {
        prefs.newArticlesNotification = currentNotificationValue & ~MANewArticlesNotificationBounce;
    }
}

/* changeMarkReadBehaviour
 * Set the mark read behaviour based on the users selection.
 */
-(IBAction)changeMarkReadBehaviour:(id)sender
{
    float newReadInterval = ([sender selectedCell] == markReadAfterNext) ? 0 : MA_Default_Read_Interval;
    [Preferences standardPreferences].markReadInterval = newReadInterval;
}

/* changeAlwaysAcceptBetas
 * Set whether Vienna will always check the cutting edge Beta when checking for updates.
 */
-(IBAction)changeAlwaysAcceptBetas:(id)sender
{
    [Preferences standardPreferences].alwaysAcceptBetas = [sender state] == NSControlStateValueOn;
}

/* dealloc
 * Clean up and release resources.
 */
-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
