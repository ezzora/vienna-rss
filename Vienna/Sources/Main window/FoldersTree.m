//
//  FoldersTree.m
//  Vienna
//
//  Created by Steve on Sat Jan 24 2004.
//  Copyright (c) 2004-2005 Steve Palmer. All rights reserved.
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

#import "FoldersTree.h"

#import "ImageAndTextCell.h"
#import "AppController.h"
#import "Constants.h"
#import "Preferences.h"
#import "HelperFunctions.h"
#import "StringExtensions.h"
#import "FolderView.h"
#import "Browser.h"
#import "OpenReader.h"
#import "Database.h"
#import "TreeNode.h"
#import "Folder.h"

@interface FoldersTree ()

@property (nonatomic, readonly, copy) NSMenu *folderMenu;

@property (nonatomic, readonly, copy) NSArray *archiveState;
@property (nonatomic) TreeNode *rootNode;
@property (nonatomic) NSFont *cellFont;
@property (nonatomic) NSFont *boldCellFont;
@property (nonatomic) NSImage *folderErrorImage;
@property (nonatomic) NSImage *refreshProgressImage;
@property (nonatomic) BOOL blockSelectionHandler;
@property (nonatomic) BOOL canRenameFolders;
@property (nonatomic) BOOL useToolTips;

-(void)setFolderListFont;
-(void)unarchiveState:(NSArray *)stateArray;
-(void)reloadDatabase:(NSArray *)stateArray;
-(BOOL)loadTree:(NSArray *)listOfFolders rootNode:(TreeNode *)node;
-(void)setManualSortOrderForNode:(TreeNode *)node;
-(void)handleDoubleClick:(id)sender;
-(void)handleAutoSortFoldersTreeChange:(NSNotification *)nc;
-(void)handleFolderAdded:(NSNotification *)nc;
-(void)handleFolderNameChange:(NSNotification *)nc;
-(void)handleFolderUpdate:(NSNotification *)nc;
-(void)handleFolderDeleted:(NSNotification *)nc;
-(void)handleShowFolderImagesChange:(NSNotification *)nc;
-(void)handleFolderFontChange:(NSNotification *)nc;
-(void)reloadFolderItem:(id)node reloadChildren:(BOOL)flag;
-(void)expandToParent:(TreeNode *)node;
-(BOOL)copyTableSelection:(NSArray *)items toPasteboard:(NSPasteboard *)pboard;
-(BOOL)moveFolders:(NSArray *)array withGoogleSync:(BOOL)sync;
-(void)enableFoldersRenaming:(id)sender;
-(void)enableFoldersRenamingAfterDelay;

@end

@implementation FoldersTree

- (instancetype)init {
	if (self = [super init]) {
		// Root node is never displayed since we always display from
		// the second level down. It simply provides a convenient way
		// of containing the other nodes.
		_rootNode = [[TreeNode alloc] init:nil atIndex:0 folder:nil canHaveChildren:YES];
		_blockSelectionHandler = NO;
		_canRenameFolders = NO;
		_useToolTips = NO;
	}

	return self;
}

/* initialiseFoldersTree
 * Do the things to initialize the folder tree from the database
 */
-(void)initialiseFoldersTree
{
	NSTableColumn * tableColumn;
	ImageAndTextCell * imageAndTextCell;

	// Our folders have images next to them.
	tableColumn = [self.outlineView tableColumnWithIdentifier:@"folderColumns"];
	imageAndTextCell = [[ImageAndTextCell alloc] init];
	[imageAndTextCell setEditable:YES];
	tableColumn.dataCell = imageAndTextCell;

	// Folder image
	self.folderErrorImage = [NSImage imageNamed:@"folderError.tiff"];
    self.folderErrorImage.accessibilityDescription = NSLocalizedString(@"Error", nil);
	self.refreshProgressImage = [NSImage imageNamed:@"refreshProgress.tiff"];
	
	// Create and set whatever font we're using for the folders
	[self setFolderListFont];

	// Allow a second click in a node to edit the node
	self.outlineView.action = @selector(handleSingleClick:);
	self.outlineView.doubleAction = @selector(handleDoubleClick:);
	self.outlineView.target = self;

	// Initially size the outline view column to be the correct width
	[self.outlineView sizeLastColumnToFit];

	// Don't resize the column when items are expanded as this messes up
	// the placement of the unread count button.
	[self.outlineView setAutoresizesOutlineColumn:NO];

	// Register for dragging
	[self.outlineView registerForDraggedTypes:@[MA_PBoardType_FolderList, MA_PBoardType_RSSSource, @"WebURLsWithTitlesPboardType", NSPasteboardTypeString]]; 
	[self.outlineView setVerticalMotionCanBeginDrag:YES];
	
	// Make sure selected row is visible
	[self.outlineView scrollRowToVisible:self.outlineView.selectedRow];

    [self.outlineView accessibilitySetOverrideValue:NSLocalizedString(@"Folders", nil) forAttribute:NSAccessibilityDescriptionAttribute];

	// Want tooltips
	self.useToolTips = YES;
	
	// Set the menu for the popup button
	self.outlineView.menu = self.folderMenu;
	
	self.blockSelectionHandler = YES;
	[self reloadDatabase:[[Preferences standardPreferences] arrayForKey:MAPref_FolderStates]];
	self.blockSelectionHandler = NO;
	
	// Register for notifications
	NSNotificationCenter * nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleFolderUpdate:) name:@"MA_Notify_FoldersUpdated" object:nil];
	[nc addObserver:self selector:@selector(handleFolderNameChange:) name:@"MA_Notify_FolderNameChanged" object:nil];
	[nc addObserver:self selector:@selector(handleFolderAdded:) name:@"MA_Notify_FolderAdded" object:nil];
	[nc addObserver:self selector:@selector(handleFolderDeleted:) name:databaseDidDeleteFolderNotification object:nil];
	[nc addObserver:self selector:@selector(handleFolderFontChange:) name:@"MA_Notify_FolderFontChange" object:nil];
	[nc addObserver:self selector:@selector(handleShowFolderImagesChange:) name:@"MA_Notify_ShowFolderImages" object:nil];
	[nc addObserver:self selector:@selector(handleAutoSortFoldersTreeChange:) name:@"MA_Notify_AutoSortFoldersTreeChange" object:nil];
    [nc addObserver:self selector:@selector(handleGRSFolderChange:) name:@"MA_Notify_GRSFolderChange" object:nil];
}

-(NSMenu *)folderMenu
{
    NSMenu *folderMenu = [[NSMenu alloc] init];

	[folderMenu addItemWithTitle:NSLocalizedString(@"Refresh Selected Subscriptions", @"Title of a menu item")
						  action:@selector(refreshSelectedSubscriptions:)
				   keyEquivalent:@""];
    [folderMenu addItem:[NSMenuItem separatorItem]];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Edit…", @"Title of a menu item")
						  action:@selector(editFolder:)
				   keyEquivalent:@""];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Rename…", @"Title of a menu item")
						  action:@selector(renameFolder:)
				   keyEquivalent:@""];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Delete…", @"Title of a menu item")
						  action:@selector(deleteFolder:)
				   keyEquivalent:@""];
    [folderMenu addItem:[NSMenuItem separatorItem]];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Mark All Articles as Read", @"Title of a menu item")
						  action:@selector(markAllRead:)
				   keyEquivalent:@""];
    [folderMenu addItem:[NSMenuItem separatorItem]];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Open Subscription Home Page", @"Title of a menu item")
						  action:@selector(viewSourceHomePage:)
				   keyEquivalent:@""];
    NSMenuItem *alternateItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Subscription Home Page in External Browser", @"Title of a menu item")
														   action:@selector(viewSourceHomePageInAlternateBrowser:)
													keyEquivalent:@""];
    alternateItem.keyEquivalentModifierMask = NSEventModifierFlagOption;
	alternateItem.alternate = YES;
    [folderMenu addItem:alternateItem];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Get Info", @"Title of a menu item")
						  action:@selector(getInfo:)
				   keyEquivalent:@""];
    [folderMenu addItem:[NSMenuItem separatorItem]];
	[folderMenu addItemWithTitle:NSLocalizedString(@"Force Refresh Selected Subscriptions From Open Reader", @"Title of a menu item")
						  action:@selector(forceRefreshSelectedSubscriptions:)
				   keyEquivalent:@""];

    return folderMenu;
}

-(void)handleGRSFolderChange:(NSNotification *)nc
{
    // No need to sync with Google because this is triggered when Open Reader
    // folder layout has changed. Making a sync call would be redundant.
    [self moveFolders:nc.object withGoogleSync:NO];
}

/* handleFolderFontChange
 * Called when the user changes the folder font and/or size in the Preferences
 */
-(void)handleFolderFontChange:(NSNotification *)nc
{
	[self setFolderListFont];
	[self.outlineView reloadData];
}

/* setFolderListFont
 * Creates or updates the fonts used by the article list. The folder
 * list isn't automatically refreshed afterward - call reloadData for that.
 */
-(void)setFolderListFont
{
	NSInteger height;


	Preferences * prefs = [Preferences standardPreferences];
	self.cellFont = [NSFont fontWithName:prefs.folderListFont size:prefs.folderListFontSize];
	self.boldCellFont = [[NSFontManager sharedFontManager] convertWeight:YES ofFont:self.cellFont];

	height = [APPCONTROLLER.layoutManager defaultLineHeightForFont:self.boldCellFont];
	self.outlineView.rowHeight = height + 5;
	self.outlineView.intercellSpacing = NSMakeSize(10, 2);
}

/* reloadDatabase
 * Refresh the folders tree and restore the specified archived state
 */
-(void)reloadDatabase:(NSArray *)stateArray
{
	[self.rootNode removeChildren];
	if (![self loadTree:[[Database sharedManager] arrayOfFolders:VNAFolderTypeRoot] rootNode:self.rootNode])
	{
		[[Preferences standardPreferences] setFoldersTreeSortMethod:MAFolderSortByName];
		[self.rootNode removeChildren];
		[self loadTree:[[Database sharedManager] arrayOfFolders:VNAFolderTypeRoot] rootNode:self.rootNode];
	}
	[self.outlineView reloadData];
	[self unarchiveState:stateArray];
}

/* saveFolderSettings
 * Preserve the expanded/collapsed and selection state of the folders list
 * into the user's preferences.
 */
-(void)saveFolderSettings
{
	[[Preferences standardPreferences] setArray:self.archiveState forKey:MAPref_FolderStates];
}

/* archiveState
 * Creates an NSArray of states for every item in the tree that has a non-normal state.
 */
-(NSArray *)archiveState
{
	NSMutableArray * archiveArray = [NSMutableArray arrayWithCapacity:16];
	NSInteger count = self.outlineView.numberOfRows;
	NSInteger index;

	for (index = 0; index < count; ++index)
	{
		TreeNode * node = (TreeNode *)[self.outlineView itemAtRow:index];
		BOOL isItemExpanded = [self.outlineView isItemExpanded:node];
		BOOL isItemSelected = [self.outlineView isRowSelected:index];

		if (isItemExpanded || isItemSelected)
		{
			NSDictionary * newDict = [NSMutableDictionary dictionary];
			[newDict setValue:@(node.nodeId) forKey:@"NodeID"];
			[newDict setValue:@(isItemExpanded) forKey:@"ExpandedState"];
			[newDict setValue:@(isItemSelected) forKey:@"SelectedState"];
			[archiveArray addObject:newDict];
		}
	}
	return [archiveArray copy];
}

/* unarchiveState
 * Unarchives an array of states.
 * BUGBUG: Restoring multiple selections is not working.
 */
-(void)unarchiveState:(NSArray *)stateArray
{
	for (NSDictionary * dict in stateArray)
	{
		NSInteger folderId = [[dict valueForKey:@"NodeID"] integerValue];
		TreeNode * node = [self.rootNode nodeFromID:folderId];
		if (node != nil)
		{
			BOOL doExpandItem = [[dict valueForKey:@"ExpandedState"] boolValue];
			BOOL doSelectItem = [[dict valueForKey:@"SelectedState"] boolValue];
			if ([self.outlineView isExpandable:node] && doExpandItem)
				[self.outlineView expandItem:node];
			if (doSelectItem)
			{
				NSInteger row = [self.outlineView rowForItem:node];
				if (row >= 0)
				{
					NSIndexSet * indexes = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
					[self.outlineView selectRowIndexes:indexes byExtendingSelection:YES];
				}
			}
		}
	}
	[self.outlineView sizeToFit];
}

/* loadTree
 * Recursive routine that populates the folder list
 */
-(BOOL)loadTree:(NSArray *)listOfFolders rootNode:(TreeNode *)node
{
	Folder * folder;
	if ([Preferences standardPreferences].foldersTreeSortMethod != MAFolderSortManual)
	{
		for (folder in listOfFolders)
		{
			NSInteger itemId = folder.itemId;
			NSArray * listOfSubFolders = [[[Database sharedManager] arrayOfFolders:itemId] sortedArrayUsingSelector:@selector(folderNameCompare:)];
			NSInteger count = listOfSubFolders.count;
			TreeNode * subNode;

			subNode = [[TreeNode alloc] init:node atIndex:-1 folder:folder canHaveChildren:(count > 0)];
			if (count)
				[self loadTree:listOfSubFolders rootNode:subNode];

		}
	}
	else
	{
		NSArray * listOfFolderIds = [listOfFolders valueForKey:@"itemId"];
		NSUInteger index = 0;
		NSInteger nextChildId = (node == self.rootNode) ? [Database sharedManager].firstFolderId : node.folder.firstChildId;
		while (nextChildId > 0)
		{
			NSUInteger  listIndex = [listOfFolderIds indexOfObject:@(nextChildId)];
			if (listIndex == NSNotFound)
			{
				NSLog(@"Cannot find child with id %ld for folder with id %ld", (long)nextChildId, (long)node.nodeId);
				return NO;
			}
			folder = listOfFolders[listIndex];
			NSArray * listOfSubFolders = [[Database sharedManager] arrayOfFolders:nextChildId];
			NSUInteger count = listOfSubFolders.count;
			TreeNode * subNode;
			
			subNode = [[TreeNode alloc] init:node atIndex:index folder:folder canHaveChildren:(count > 0)];
			if (count)
			{
				if (![self loadTree:listOfSubFolders rootNode:subNode])
				{
					return NO;
				}
			}
			nextChildId = folder.nextSiblingId;
			++index;
		}
		if (index < listOfFolders.count)
		{
			NSLog(@"Missing children for folder with id %ld, %ld", (long)nextChildId, (long)node.nodeId);
			return NO;
		}
	}
	return YES;
}

/* folders
 * Returns an array that contains the all RSS folders in the database
 * ordered by the order in which they appear in the folders list view.
 */
-(NSArray *)folders:(NSInteger)folderId
{
	NSMutableArray * array = [NSMutableArray array];
	TreeNode * node;

    if (!folderId) {
		node = self.rootNode;
    } else {
		node = [self.rootNode nodeFromID:folderId];
    }
    if (node.folder != nil && (node.folder.type == VNAFolderTypeRSS || node.folder.type == VNAFolderTypeOpenReader)) {
		[array addObject:node.folder];
    }
	node = node.firstChild;
	while (node != nil)
	{
		[array addObjectsFromArray:[self folders:node.nodeId]];
		node = node.nextSibling;
	}
	return [array copy];
}

/* children
 * Returns an array that contains the children folders in the database
 * ordered by the order in which they appear in the folders list view.
 */
-(NSArray *)children:(NSInteger)folderId
{
	NSMutableArray * array = [NSMutableArray array];
	TreeNode * node;

	if (!folderId)
		node = self.rootNode;
	else
		node = [self.rootNode nodeFromID:folderId];
	node = node.firstChild;
	while (node != nil)
	{
		[array addObject:node.folder];
		node = node.nextSibling;
	}
	return [array copy];
}

/* updateAlternateMenuTitle
 * Sets the appropriate title for the alternate item in the contextual menu
 * when user changes preferences for opening pages in external browser
 */
-(void)updateAlternateMenuTitle
{
	NSMenuItem * mainMenuItem = menuItemWithAction(@selector(viewSourceHomePageInAlternateBrowser:));
	if (mainMenuItem == nil)
		return;
	NSString * menuTitle = mainMenuItem.title;
	NSInteger index;
	NSMenu * folderMenu = self.outlineView.menu;
	if (folderMenu != nil)
	{
		index = [folderMenu indexOfItemWithTarget:nil andAction:@selector(viewSourceHomePageInAlternateBrowser:)];
		if (index >= 0)
		{
			NSMenuItem * contextualItem = [folderMenu itemAtIndex:index];
			contextualItem.title = menuTitle;
		}
	}
}

/* updateFolder
 * Redraws a folder node and optionally recurses up and redraws all our
 * parent nodes too.
 */
-(void)updateFolder:(NSInteger)folderId recurseToParents:(BOOL)recurseToParents
{
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	if (node != nil)
	{
		[self.outlineView reloadItem:node reloadChildren:YES];
		if (recurseToParents)
		{
			while (node.parentNode != self.rootNode)
			{
				node = node.parentNode;
				[self.outlineView reloadItem:node];
			}
		}
	}
}

/* canDeleteFolderAtRow
 * Returns YES if the folder at the specified row can be deleted, otherwise NO.
 */
-(BOOL)canDeleteFolderAtRow:(NSInteger)row
{
	if (row >= 0)
	{
		TreeNode * node = [self.outlineView itemAtRow:row];
		if (node != nil)
		{
			Folder * folder = [[Database sharedManager] folderFromID:node.nodeId];
			return folder && folder.type != VNAFolderTypeSearch && folder.type != VNAFolderTypeTrash && ![Database sharedManager].readOnly && self.outlineView.window.visible;
		}
	}
	return NO;
}

/* selectFolder
 * Move the selection to the specified folder and make sure
 * it's visible in the UI.
 */
-(BOOL)selectFolder:(NSInteger)folderId
{
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	if (!node)
		return NO;

	// Walk up to our parent
	[self expandToParent:node];
	NSInteger rowIndex = [self.outlineView rowForItem:node];
	if (rowIndex >= 0)
	{
		self.blockSelectionHandler = YES;
		[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex] byExtendingSelection:NO];
		[self.outlineView scrollRowToVisible:rowIndex];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_FolderSelectionChange" object:node];
		self.blockSelectionHandler = NO;
		return YES;
	}
	return NO;
}

/* expandToParent
 * Expands the parent nodes all the way up to the root to ensure
 * that the node containing 'node' is visible.
 */
-(void)expandToParent:(TreeNode *)node
{
	if (node.parentNode)
	{
		[self expandToParent:node.parentNode];
		[self.outlineView expandItem:node.parentNode];
	}
}

/* nextFolderWithUnreadAfterNode
 * Finds the ID of the next folder after the specified node that has
 * unread articles.
 */
-(NSInteger)nextFolderWithUnreadAfterNode:(TreeNode *)startingNode
{
    // keep track of parent (or grandparent) of starting node
    TreeNode * parentOfStartingNode = startingNode;
    while (parentOfStartingNode != nil && parentOfStartingNode.parentNode != self.rootNode)
    {
        parentOfStartingNode = parentOfStartingNode.parentNode;
    }
	TreeNode * node = startingNode;

	while (node != nil)
	{
		TreeNode * nextNode = nil;
		TreeNode * parentNode = node.parentNode;
		if ((node.folder.childUnreadCount > 0) && [self.outlineView isItemExpanded:node])
			nextNode = node.firstChild;
		if (nextNode == nil)
			nextNode = node.nextSibling;
		while (nextNode == nil && parentNode != nil)
		{
			nextNode = parentNode.nextSibling;
			parentNode = parentNode.parentNode;
		}
		if (nextNode == nil)
			nextNode = self.rootNode.firstChild;

		if ((nextNode.folder.childUnreadCount) && ![self.outlineView isItemExpanded:nextNode])
			return nextNode.nodeId;
		
		if (nextNode.folder.unreadCount)
			return nextNode.nodeId;

		// If we've gone full circle and not found
		// anything, we're out of unread articles
		if (nextNode == startingNode
            || (nextNode == parentOfStartingNode && !nextNode.folder.childUnreadCount))
        {
			return startingNode.nodeId;
		}

		node = nextNode;
	}
	return -1;
}

/* firstFolderWithUnread
 * Finds the ID of the first folder that has unread articles.
 */
-(NSInteger)firstFolderWithUnread
{
	// Get the first Node from the root node.
	TreeNode * firstNode = self.rootNode.firstChild;
	
	// Now get the ID of the next unread node after it and return it.
	NSInteger nextNodeID = [self nextFolderWithUnreadAfterNode:firstNode];
	return nextNodeID;
}

/* nextFolderWithUnread
 * Finds the ID of the next folder after currentFolderId that has
 * unread articles.
 */
-(NSInteger)nextFolderWithUnread:(NSInteger)currentFolderId
{
	// Get the current Node from the ID.
	TreeNode * currentNode = [self.rootNode nodeFromID:currentFolderId];
	
	// Now get the ID of the next unread node after it and return it.
	NSInteger nextNodeID = [self nextFolderWithUnreadAfterNode:currentNode];
	return nextNodeID;
}

/* groupParentSelection
 * If the selected folder is a group folder, it returns the ID of the group folder
 * otherwise it returns the ID of the parent folder.
 */
-(NSInteger)groupParentSelection
{
	Folder * folder = [[Database sharedManager] folderFromID:self.actualSelection];
	return folder ? ((folder.type == VNAFolderTypeGroup) ? folder.itemId : folder.parentId) : VNAFolderTypeRoot;
}

/* actualSelection
 * Return the ID of the selected folder in the folder list.
 */
-(NSInteger)actualSelection
{
	TreeNode * node = [self.outlineView itemAtRow:self.outlineView.selectedRow];
	return node.nodeId;
}

/* countOfSelectedFolders
 * Return the total number of folders selected in the tree.
 */
-(NSInteger)countOfSelectedFolders
{
	return self.outlineView.numberOfSelectedRows;
}

/* selectedFolders
 * Returns an exclusive array of all selected folders. Exclusive means that if any folder is
 * a group folder, we don't automatically return a list of all folders within that group.
 */
-(NSArray *)selectedFolders
{
	NSIndexSet * rowIndexes = self.outlineView.selectedRowIndexes;
	NSUInteger count = rowIndexes.count;
	
	// Make a mutable array
	NSMutableArray * arrayOfSelectedFolders = [NSMutableArray arrayWithCapacity:count];

	if (count > 0)
	{
		NSUInteger index = rowIndexes.firstIndex;
		while (index != NSNotFound)
		{
			TreeNode * node = [self.outlineView itemAtRow:index];
			Folder * folder = node.folder;
			if (folder != nil)
			{
				[arrayOfSelectedFolders addObject:folder];
			}
			index = [rowIndexes indexGreaterThanIndex:index];
		}
	}
	
	return [arrayOfSelectedFolders copy];
}

/* setManualSortOrderForNode
 * Writes the order of the current folder hierarchy to the database.
 */
-(void)setManualSortOrderForNode:(TreeNode *)node
{
    if (node == nil) {
		return;
    }
	NSInteger folderId = node.nodeId;
    Database *dbManager = [Database sharedManager];
	
	NSInteger count = node.countOfChildren;
	if (count > 0)
	{
		
        [dbManager setFirstChild:[node childByIndex:0].nodeId forFolder:folderId];
		[self setManualSortOrderForNode:[node childByIndex:0]];
		NSInteger index;
		for (index = 1; index < count; ++index)
		{
			[dbManager setNextSibling:[node childByIndex:index].nodeId forFolder:[node childByIndex:index - 1].nodeId];
			[self setManualSortOrderForNode:[node childByIndex:index]];
		}
		[dbManager setNextSibling:0 forFolder:[node childByIndex:index - 1].nodeId];
	}
    else {
		[dbManager setFirstChild:0 forFolder:folderId];
    }
}

/* handleAutoSortFoldersTreeChange
 * Respond to the notification when the preference is changed for automatically or manually sorting the folders tree.
 */
-(void)handleAutoSortFoldersTreeChange:(NSNotification *)nc
{
	NSInteger selectedFolderId = self.actualSelection;
	
	if ([Preferences standardPreferences].foldersTreeSortMethod == MAFolderSortManual)
	{
        [self setManualSortOrderForNode:self.rootNode];
	}
	
	self.blockSelectionHandler = YES;
	[self reloadDatabase:[[Preferences standardPreferences] arrayForKey:MAPref_FolderStates]];
	self.blockSelectionHandler = NO;
	
	// Make sure selected folder is visible
	[self selectFolder:selectedFolderId];
}

/* handleShowFolderImagesChange
 * Respond to the notification sent when the option to show folder images is changed.
 */
-(void)handleShowFolderImagesChange:(NSNotification *)nc
{
	[self.outlineView reloadData];
}

/* handleSingleClick
 * If the folder is already highlighted, then edit the folder name.
 */
-(void)handleSingleClick:(id)sender
{
	if (self.canRenameFolders)
	{
		NSInteger clickedRow = self.outlineView.clickedRow;
		if (clickedRow >= 0)
			[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(renameFolderByTimer:) userInfo:[self.outlineView itemAtRow:clickedRow] repeats:NO];
	}
}

/* handleDoubleClick
 * Handle the user double-clicking a node.
 */
-(void)handleDoubleClick:(id)sender
{
	// Prevent the first click of the double click from triggering immediate folder name editing.
	[self enableFoldersRenamingAfterDelay];
	
	TreeNode * node = [self.outlineView itemAtRow:self.outlineView.selectedRow];

	if (node.folder.type == VNAFolderTypeRSS || node.folder.type == VNAFolderTypeOpenReader)
	{
		NSString * urlString = node.folder.homePage;
        if (urlString && !urlString.blank) {
			[APPCONTROLLER openURLFromString:urlString inPreferredBrowser:YES];
        }
	}
	else if (node.folder.type == VNAFolderTypeSmart) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_EditFolder" object:node];
	}
}

/* handleFolderDeleted
 * Called whenever a folder is removed from the database. We need
 * to delete the associated tree nodes then select the next node, or
 * the previous one if we were at the bottom of the list.
 */
-(void)handleFolderDeleted:(NSNotification *)nc
{
	NSInteger currentFolderId = self.controller.currentFolderId;
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	TreeNode * thisNode = [self.rootNode nodeFromID:folderId];
	TreeNode * nextNode;
	
	// Stop any in process progress indicators.
	[thisNode stopAndReleaseProgressIndicator];

	// First find the next node we'll select
	if (thisNode.nextSibling != nil)
		nextNode = thisNode.nextSibling;
	else
	{
		nextNode = thisNode.parentNode;
		if (nextNode.countOfChildren > 1)
			nextNode = [nextNode childByIndex:nextNode.countOfChildren - 2];
	}

	// Ask our parent to delete us
	TreeNode * ourParent = thisNode.parentNode;
	[ourParent removeChild:thisNode andChildren:YES];
	[self reloadFolderItem:ourParent reloadChildren:YES];

	// Send the selection notification ourselves because if we're deleting at the end of
	// the folder list, the selection won't actually change and outlineViewSelectionDidChange
	// won't get tripped.
	if (currentFolderId == folderId)
	{
		self.blockSelectionHandler = YES;
		[self selectFolder:nextNode.nodeId];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_FolderSelectionChange" object:nextNode];
		self.blockSelectionHandler = NO;
	}
}

/* handleFolderNameChange
 * Called whenever we need to redraw a specific folder, possibly because
 * the unread count changed.
 */
-(void)handleFolderNameChange:(NSNotification *)nc
{
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	TreeNode * parentNode = node.parentNode;

	BOOL moveSelection = (folderId == self.actualSelection);

	if ([Preferences standardPreferences].foldersTreeSortMethod == MAFolderSortByName)
		[parentNode sortChildren:MAFolderSortByName];

	[self reloadFolderItem:parentNode reloadChildren:YES];
	if (moveSelection)
	{
		NSInteger row = [self.outlineView rowForItem:node];
		if (row >= 0)
		{
			self.blockSelectionHandler = YES;
			NSIndexSet * indexes = [NSIndexSet indexSetWithIndex:(NSUInteger)row];
			[self.outlineView selectRowIndexes:indexes byExtendingSelection:NO];
			[self.outlineView scrollRowToVisible:row];
			self.blockSelectionHandler = NO;
		}
	}
}

/* handleFolderUpdate
 * Called whenever we need to redraw a specific folder, possibly because
 * the unread count changed.
 */
-(void)handleFolderUpdate:(NSNotification *)nc
{
	NSInteger folderId = ((NSNumber *)nc.object).integerValue;
	if (folderId == 0)
		[self reloadFolderItem:self.rootNode reloadChildren:YES];
	else
		[self updateFolder:folderId recurseToParents:YES];
}

/* handleFolderAdded
 * Called when a new folder is added to the database.
 */
-(void)handleFolderAdded:(NSNotification *)nc
{
	Folder * newFolder = (Folder *)nc.object;
	NSAssert(newFolder, @"Somehow got a NULL folder object here");

	NSInteger parentId = newFolder.parentId;
	TreeNode * node = (parentId == VNAFolderTypeRoot) ? self.rootNode : [self.rootNode nodeFromID:parentId];
	if (!node.canHaveChildren)
		[node setCanHaveChildren:YES];
	
	NSInteger childIndex = -1;
	if ([Preferences standardPreferences].foldersTreeSortMethod == MAFolderSortManual)
	{
		NSInteger nextSiblingId = newFolder.nextSiblingId;
		if (nextSiblingId > 0)
		{
			TreeNode * nextSibling = [node nodeFromID:nextSiblingId];
			if (nextSibling != nil)
				childIndex = [node indexOfChild:nextSibling];
		}
	}
	
	TreeNode __unused * newNode = [[TreeNode alloc] init:node atIndex:childIndex folder:newFolder canHaveChildren:NO];
	[self reloadFolderItem:node reloadChildren:YES];
	[self selectFolder:newFolder.itemId];
}

/* reloadFolderItem
 * Wrapper around reloadItem.
 */
-(void)reloadFolderItem:(id)node reloadChildren:(BOOL)flag
{
	if (node == self.rootNode)
		[self.outlineView reloadData];
	else
		[self.outlineView reloadItem:node reloadChildren:YES];
}

/* menuWillAppear
 * Called when the popup menu is opened on the folder list. We move the
 * selection to whichever node is under the cursor so the context between
 * the menu items and the node is made clear.
 */
-(void)outlineView:(FolderView *)olv menuWillAppear:(NSEvent *)theEvent
{
	NSInteger row = [olv rowAtPoint:[olv convertPoint:theEvent.locationInWindow fromView:nil]];
	if (row >= 0)
	{
		// Select the row under the cursor if it isn't already selected
		if (olv.numberOfSelectedRows <= 1)
			[olv selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
	}
}

/* isItemExpandable
 * Tell the outline view if the specified item can be expanded. The answer is
 * yes if we have children, no otherwise.
 */
-(BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	TreeNode * node = (TreeNode *)item;
	if (node == nil)
		node = self.rootNode;
	return node.canHaveChildren;
}

/* numberOfChildrenOfItem
 * Returns the number of children belonging to the specified item
 */
-(NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	TreeNode * node = (TreeNode *)item;
	if (node == nil)
		node = self.rootNode;
	return node.countOfChildren;
}

/* child
 * Returns the child at the specified offset of the item
 */
-(id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	TreeNode * node = (TreeNode *)item;
	if (node == nil)
		node = self.rootNode;
	return [node childByIndex:index];
}

/* outlineView:tooltipForCell:rect:tableColumn:item:mouseLocation: [delegate]
 * For items that have counts, we show a tooltip that aggregates the counts.
 */
- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation
{
	TreeNode * node = (TreeNode *)item;
	if (self.useToolTips && node != nil)
	{
		if (node.folder.nonPersistedFlags & VNAFolderFlagError)
			return NSLocalizedString(@"An error occurred when this feed was last refreshed", nil);
		NSInteger unreadCount;
		if (node.folder.childUnreadCount) {
		    unreadCount = node.folder.childUnreadCount;
		} else {
		    unreadCount = node.folder.unreadCount;
		}
		if (unreadCount) {
			return [NSString stringWithFormat:NSLocalizedString(@"%d unread articles", nil), unreadCount];
		}
	}
	return nil;
}

/* objectValueForTableColumn
 * Returns the actual string that is displayed in the cell. Folders that have child folders with unread
 * articles show the aggregate unread article count.
 */
-(id)outlineView:(NSOutlineView *)olv objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	TreeNode * node = (TreeNode *)item;
	if (node == nil)
		node = self.rootNode;

	static NSDictionary * info = nil;
	if (info == nil)
	{
		NSMutableParagraphStyle * style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		style.lineBreakMode = NSLineBreakByTruncatingTail;
		style.tighteningFactorForTruncation = 0.0;
		style.alignment = NSTextAlignmentLeft;
		info = @{NSParagraphStyleAttributeName: style};
	}

	Folder * folder = node.folder;
    NSMutableDictionary * myInfo = [NSMutableDictionary dictionaryWithDictionary:info];
    if (folder.isUnsubscribed) {
        if (@available(macOS 10.10, *)) {
            myInfo[NSForegroundColorAttributeName] = NSColor.secondaryLabelColor;
        } else {
            myInfo[NSForegroundColorAttributeName] = NSColor.disabledControlTextColor;
        }
    } else {
		if (@available(macOS 10.10, *)) {
			myInfo[NSForegroundColorAttributeName] = NSColor.labelColor;
		} else {
			myInfo[NSForegroundColorAttributeName] = NSColor.controlTextColor;
		}
    }
	// Set the font
	if (folder.unreadCount ||  (folder.childUnreadCount && ![olv isItemExpanded:item]))
		myInfo[NSFontAttributeName] = self.boldCellFont;
	else
		myInfo[NSFontAttributeName] = self.cellFont;
	
	return [[NSAttributedString alloc] initWithString:node.nodeName attributes:myInfo];
}

/* willDisplayCell
 * Hook before a cell is displayed to set the correct image for that cell. We use this to show the folder
 * in normal or bold face depending on whether or not the folder (or sub-folders) have unread articles. This
 * is also the place where we set the folder image.
 */
-(void)outlineView:(NSOutlineView *)olv willDisplayCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item 
{
	if ([tableColumn.identifier isEqualToString:@"folderColumns"]) 
	{
		TreeNode * node = (TreeNode *)item;
		Folder * folder = node.folder;
		ImageAndTextCell * realCell = (ImageAndTextCell *)cell;

		// Use the auxiliary position of the feed item to show
		// the refresh icon if the feed is being refreshed, or an
		// error icon if the feed failed to refresh last time.
		if (folder.isUpdating)
		{
			[realCell setAuxiliaryImage:nil];
			[realCell setInProgress:YES];
		}
		else if (folder.isError)
		{
			realCell.auxiliaryImage = self.folderErrorImage;
			[realCell setInProgress:NO];
		}
		else
		{
			[realCell setAuxiliaryImage:nil];
			[realCell setInProgress:NO];
		}

		if (folder.type == VNAFolderTypeSmart)  // Because if the search results contain unread articles we don't want the smart folder name to be bold.
		{
			[realCell clearCount];
		}
		else if (folder.unreadCount)
		{
			[realCell setCount:folder.unreadCount];
			[realCell setCountBackgroundColour:[NSColor colorForControlTint:[NSColor currentControlTint]]];
		}
		else if (folder.childUnreadCount && ![olv isItemExpanded:item])
		{
			[realCell setCount:folder.childUnreadCount];
			[realCell setCountBackgroundColour:[NSColor colorForControlTint:[NSColor currentControlTint]]];
		}
		else
		{
			[realCell clearCount];
		}

		// Only show folder images if the user prefers them.
		Preferences * prefs = [Preferences standardPreferences];
		realCell.image = (prefs.showFolderImages ? folder.image : [folder standardImage]);

		[realCell setItem:item];
	}
}

/* mainView
 * Return the main view of this class.
 */
-(NSView *)mainView
{
	return self.outlineView;
}

/* outlineViewSelectionDidChange
 * Called when the selection in the folder list has changed.
 */
-(void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	[self enableFoldersRenamingAfterDelay];
	
	if (!self.blockSelectionHandler)
	{
		TreeNode * node = [self.outlineView itemAtRow:self.outlineView.selectedRow];
		[[NSNotificationCenter defaultCenter] postNotificationName:@"MA_Notify_FolderSelectionChange" object:node];
	}
}

/* renameFolder
 * Begin in-place editing of the selected folder name.
 */
-(void)renameFolder:(NSInteger)folderId
{	
	TreeNode * node = [self.rootNode nodeFromID:folderId];
	NSInteger rowIndex = [self.outlineView rowForItem:node];
		
	if (rowIndex != -1)
	{
		[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)rowIndex] byExtendingSelection:NO];
		[self.outlineView editColumn:[self.outlineView columnWithIdentifier:@"folderColumns"] row:rowIndex withEvent:nil select:YES];
	}
}

/* renameFolderByTimer
 * If no disabling events have occurred during the timer interval, rename the folder.
 */
-(void)renameFolderByTimer:(id)sender
{
	if (self.canRenameFolders)
	{
		[self renameFolder:((TreeNode *)[sender userInfo]).nodeId];
	}
}

/* enableFoldersRenaming
 * Enable the renaming of folders.
 */
-(void)enableFoldersRenaming:(id)sender
{
	self.canRenameFolders = YES;
}

/* enableFoldersRenamingAfterDelay
 * Set a timer to enable renaming of folders.
 */
-(void)enableFoldersRenamingAfterDelay
{
	self.canRenameFolders = NO;
	[NSTimer scheduledTimerWithTimeInterval:[NSEvent doubleClickInterval] target:self selector:@selector(enableFoldersRenaming:) userInfo:nil repeats:NO];
}

/* outlineViewWillBecomeFirstResponder
 * When outline view becomes first responder, bring the article view to the front,
 * and prevent immediate folder renaming.
 */
-(void)outlineViewWillBecomeFirstResponder
{
	[self.controller.browser setActiveTabToPrimaryTab];
	[self enableFoldersRenamingAfterDelay];
}

/* shouldEditTableColumn [delegate]
 * The editing of folder names will be handled by single clicks.
 */
-(BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	return NO;
}

/* setObjectValue [datasource]
 * Update the folder name when the user has finished editing it.
 */
-(void)outlineView:(NSOutlineView *)olv setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
	TreeNode * node = (TreeNode *)item;
	NSString * newName = (NSString *)object;
	Folder * folder = node.folder;
	
	// Remove the "☁️ " symbols on Open Reader feeds
	if (folder.type == VNAFolderTypeOpenReader && [newName hasPrefix:@"☁️ "]) {
		NSString *tmpName = [newName substringFromIndex:3];
		newName = tmpName;
	}
	
	if (![folder.name isEqualToString:newName])
	{
		Database * dbManager = [Database sharedManager];
		if ([dbManager folderFromName:newName] != nil)
			runOKAlertPanel(NSLocalizedString(@"Cannot rename folder", nil), NSLocalizedString(@"A folder with that name already exists", nil));
		else
        {
            [dbManager setName:newName forFolder:folder.itemId];
            if (folder.type == VNAFolderTypeOpenReader) {
                [[OpenReader sharedManager] setFolderTitle:newName forFeed:folder.feedURL];
            }
        }
	}
}

/* validateDrop
 * Called when something is being dragged over us. We respond with an NSDragOperation value indicating the
 * feedback for the user given where we are.
 */
-(NSDragOperation)outlineView:(NSOutlineView*)olv validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
	NSPasteboard * pb = [info draggingPasteboard]; 
	NSString * type = [pb availableTypeFromArray:@[MA_PBoardType_FolderList, MA_PBoardType_RSSSource, @"WebURLsWithTitlesPboardType", NSPasteboardTypeString]]; 
	NSDragOperation dragType = ([type isEqualToString:MA_PBoardType_FolderList]) ? NSDragOperationMove : NSDragOperationCopy;

	TreeNode * node = (TreeNode *)item;
	BOOL isOnDropTypeProposal = index == NSOutlineViewDropOnItemIndex;

	// Can't drop anything onto the trash folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeTrash) {
		return NSDragOperationNone;
    }

	// Can't drop anything onto the search folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeSearch) {
		return NSDragOperationNone;
    }
	
	// Can't drop anything on smart folders.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeSmart) {
		return NSDragOperationNone;
    }
	
	// Can always drop something on a group folder.
    if (isOnDropTypeProposal && node != nil && node.folder.type == VNAFolderTypeGroup) {
		return dragType;
    }
	
	// For any other folder, can't drop anything ON them.
    if (index == NSOutlineViewDropOnItemIndex) {
		return NSDragOperationNone;
    }
	return NSDragOperationGeneric; 
}

/* writeItems [delegate]
 * Collect the selected folders ready for dragging.
 */
-(BOOL)outlineView:(NSOutlineView *)olv writeItems:(NSArray*)items toPasteboard:(NSPasteboard*)pboard
{
	return [self copyTableSelection:items toPasteboard:pboard];
}

/* copyTableSelection
 * This is the common copy selection code. We build an array of dictionary entries each of
 * which include details of each selected folder in the standard RSS item format defined by
 * Ranchero NetNewsWire. See http://ranchero.com/netnewswire/rssclipboard.php for more details.
 */
-(BOOL)copyTableSelection:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
	NSInteger count = items.count;
	NSMutableArray * externalDragData = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray * internalDragData = [NSMutableArray arrayWithCapacity:count];
	NSMutableString * stringDragData = [NSMutableString string];
	NSMutableArray * arrayOfURLs = [NSMutableArray arrayWithCapacity:count];
	NSMutableArray * arrayOfTitles = [NSMutableArray arrayWithCapacity:count];
	NSInteger index;

	// We'll create the types of data on the clipboard.
	[pboard declareTypes:@[MA_PBoardType_FolderList, MA_PBoardType_RSSSource, @"WebURLsWithTitlesPboardType", NSPasteboardTypeString] owner:self]; 

	// Create an array of NSNumber objects containing the selected folder IDs.
	NSInteger countOfItems = 0;
	for (index = 0; index < count; ++index)
	{
		TreeNode * node = items[index];
		Folder * folder = node.folder;

		if (folder.type == VNAFolderTypeRSS
            || folder.type == VNAFolderTypeOpenReader
            || folder.type == VNAFolderTypeSmart
            || folder.type == VNAFolderTypeGroup
            || folder.type == VNAFolderTypeSearch
            || folder.type == VNAFolderTypeTrash) {
			[internalDragData addObject:@(node.nodeId)];
			++countOfItems;
		}

		if (folder.type == VNAFolderTypeRSS
            || folder.type == VNAFolderTypeOpenReader) {
			NSString * feedURL = folder.feedURL;
			
			NSMutableDictionary * dict = [NSMutableDictionary dictionary];
			[dict setValue:folder.name forKey:@"sourceName"];
			[dict setValue:folder.description forKey:@"sourceDescription"];
			[dict setValue:feedURL forKey:@"sourceRSSURL"];
			[dict setValue:folder.homePage forKey:@"sourceHomeURL"];
			[externalDragData addObject:dict];

			[stringDragData appendFormat:@"%@\n", feedURL];
			
			NSURL * safariURL = [NSURL URLWithString:feedURL];
			if (safariURL != nil && !safariURL.fileURL)
			{
				if (![@"feed" isEqualToString:safariURL.scheme])
				{
					feedURL = [NSString stringWithFormat:@"feed:%@", safariURL.resourceSpecifier];
				}
				[arrayOfURLs addObject:feedURL];
				[arrayOfTitles addObject:folder.name];
			}
		}
	}

	// Copy the data to the pasteboard 
	[pboard setPropertyList:externalDragData forType:MA_PBoardType_RSSSource];
	[pboard setString:stringDragData forType:NSPasteboardTypeString];
	[pboard setPropertyList:internalDragData forType:MA_PBoardType_FolderList]; 
	[pboard setPropertyList:@[arrayOfURLs, arrayOfTitles] forType:@"WebURLsWithTitlesPboardType"]; 
	return countOfItems > 0; 
}

/* moveFoldersUndo
 * Undo handler to move folders back.
 */
-(void)moveFoldersUndo:(id)anObject
{
	[self moveFolders:(NSArray *)anObject withGoogleSync:YES];
}

/* moveFolders
 * Reparent folders using the information in the specified array. The array consists of
 * a collection of NSNumber triples: the first number is the ID of the folder to move,
 * the second number is the ID of the parent to which the folder should be moved,
 * the third number is the ID of the folder's new predecessor sibling.
 */
-(BOOL)moveFolders:(NSArray *)array withGoogleSync:(BOOL)sync
{
	NSAssert(([array count] % 3) == 0, @"Incorrect number of items in array passed to moveFolders");
	NSInteger count = array.count;
	__block NSInteger index = 0;

	// Need to create a running undo array
	NSMutableArray * undoArray = [[NSMutableArray alloc] initWithCapacity:count];

	// Internal drag and drop so we're just changing the parent IDs around. One thing
	// we have to watch for is to make sure that we don't re-parent to a subordinate
	// folder.
	Database * dbManager = [Database sharedManager];
	BOOL autoSort = [Preferences standardPreferences].foldersTreeSortMethod != MAFolderSortManual;

	while (index < count)
	{
		NSInteger folderId = [array[index++] integerValue];
		NSInteger newParentId = [array[index++] integerValue];
		NSInteger newPredecessorId = [array[index++] integerValue];
		Folder * folder = [dbManager folderFromID:folderId];
		NSInteger oldParentId = folder.parentId;
		
		TreeNode * node = [self.rootNode nodeFromID:folderId];
		TreeNode * oldParent = [self.rootNode nodeFromID:oldParentId];
		NSInteger oldChildIndex = [oldParent indexOfChild:node];
		NSInteger oldPredecessorId = (oldChildIndex > 0) ? [oldParent childByIndex:(oldChildIndex - 1)].nodeId : 0;
		TreeNode * newParent = [self.rootNode nodeFromID:newParentId];
		TreeNode * newPredecessor = [newParent nodeFromID:newPredecessorId];
		if ((newPredecessor == nil) || (newPredecessor == newParent))
			newPredecessorId = 0;
		NSInteger newChildIndex = (newPredecessorId > 0) ? ([newParent indexOfChild:newPredecessor] + 1) : 0;
        
		if (newParentId == oldParentId)
		{
			// With automatic sorting, moving under the same parent is impossible.
            if (autoSort) {
				continue;
            }
			// No need to move if destination is the same as origin.
            if (newPredecessorId == oldPredecessorId) {
				continue;
            }
			// Adjust the index for the removal of the old child.
            if (newChildIndex > oldChildIndex) {
                --newChildIndex;
            }
				
		}
		else
		{
			if (!newParent.canHaveChildren)
				[newParent setCanHaveChildren:YES];
			if ([dbManager setParent:newParentId forFolder:folderId])
			{
				if (folder.type == VNAFolderTypeOpenReader)
				{
					OpenReader * myGoogle = [OpenReader sharedManager];
					// remove old label
					NSString * folderName = [dbManager folderFromID:oldParentId].name;
					[myGoogle setFolderLabel:folderName forFeed:folder.feedURL set:FALSE];
					// add new label
					folderName = [dbManager folderFromID:newParentId].name;
					[myGoogle setFolderLabel:folderName forFeed:folder.feedURL set:TRUE];
				}
			}
			else
				continue;
		}
		
		if (!autoSort)
		{
			if (oldPredecessorId > 0)
			{
				if (![dbManager setNextSibling:folder.nextSiblingId forFolder:oldPredecessorId])
					continue;
			}
			else
			{
				if (![dbManager setFirstChild:folder.nextSiblingId forFolder:oldParentId])
					continue;
			}
		}
		
		[oldParent removeChild:node andChildren:NO];
		[newParent addChild:node atIndex:newChildIndex];
		
		// Put at beginning of undoArray in order to undo moves in reverse order.
		[undoArray insertObject:@(folderId) atIndex:0u];
		[undoArray insertObject:@(oldParentId) atIndex:1u];
		[undoArray insertObject:@(oldPredecessorId) atIndex:2u];
		
		if (!autoSort)
		{
			if (newPredecessorId > 0)
			{
				if (![dbManager setNextSibling:[dbManager folderFromID:newPredecessorId].nextSiblingId
                                     forFolder:folderId]) {
					continue;
                }
				[dbManager setNextSibling:folderId forFolder:newPredecessorId];
			}
			else
			{
				NSInteger oldFirstChildId = (newParent == self.rootNode) ? dbManager.firstFolderId : newParent.folder.firstChildId;
				if (![dbManager setNextSibling:oldFirstChildId forFolder:folderId])
					continue;
				[dbManager setFirstChild:folderId forFolder:newParentId];
			}
		}
	}
	
	// If undo array is empty, then nothing has been moved.
	if (undoArray.count == 0u)
	{
		return NO;
	}
	
	// Set up to undo this action
	NSUndoManager * undoManager = NSApp.mainWindow.undoManager;
	[undoManager registerUndoWithTarget:self selector:@selector(moveFoldersUndo:) object:undoArray];
	[undoManager setActionName:NSLocalizedString(@"Move Folders", nil)];
	
	// Make the outline control reload its data
	[self.outlineView reloadData];

	// If any parent was a collapsed group, expand it now
	for (index = 0; index < count; index += 2)
	{
		NSInteger newParentId = [array[++index] integerValue];
		if (newParentId != VNAFolderTypeRoot)
		{
			TreeNode * parentNode = [self.rootNode nodeFromID:newParentId];
			if (![self.outlineView isItemExpanded:parentNode] && [self.outlineView isExpandable:parentNode])
				[self.outlineView expandItem:parentNode];
		}
	}
	
	// Properly set selection back to the original items. This has to be done after the
	// refresh so that rowForItem returns the new positions.
	NSMutableIndexSet * selIndexSet = [[NSMutableIndexSet alloc] init];
	NSInteger selRowIndex = 9999;
	for (index = 0; index < count; index += 2)
	{
		NSInteger folderId = [array[index++] integerValue];
		NSInteger rowIndex = [self.outlineView rowForItem:[self.rootNode nodeFromID:folderId]];
		selRowIndex = MIN(selRowIndex, rowIndex);
		[selIndexSet addIndex:rowIndex];
	}
	[self.outlineView scrollRowToVisible:selRowIndex];
	[self.outlineView selectRowIndexes:selIndexSet byExtendingSelection:NO];
	return YES;
}

/* acceptDrop
 * Accept a drop on or between nodes either from within the folder view or from outside.
 */
-(BOOL)outlineView:(NSOutlineView *)olv acceptDrop:(id <NSDraggingInfo>)info item:(id)targetItem childIndex:(NSInteger)child
{ 
	__block NSInteger childIndex = child;
	NSPasteboard * pb = [info draggingPasteboard];
	NSString * type = [pb availableTypeFromArray:@[MA_PBoardType_FolderList, MA_PBoardType_RSSSource, @"WebURLsWithTitlesPboardType", NSPasteboardTypeString]];
	TreeNode * node = targetItem ? (TreeNode *)targetItem : self.rootNode;

	NSInteger parentId = node.nodeId;
	if ((childIndex == NSOutlineViewDropOnItemIndex) || (childIndex < 0))
		childIndex = 0;

	// Check the type
	if ([type isEqualToString:NSPasteboardTypeString])
	{
		// This is possibly a URL that we'll handle as a potential feed subscription. It's
		// not our call to make though.
		NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
		[APPCONTROLLER createNewSubscription:[pb stringForType:type] underFolder:parentId afterChild:predecessorId];
		return YES;
	}
	if ([type isEqualToString:MA_PBoardType_FolderList])
	{
		Database * db = [Database sharedManager];
		NSArray * arrayOfSources = [pb propertyListForType:type];
		NSInteger count = arrayOfSources.count;
		NSInteger index;
		NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;

		// Create an NSArray of triples (folderId, newParentId, predecessorId) that will be passed to moveFolders
		// to do the actual move.
		NSMutableArray * array = [[NSMutableArray alloc] initWithCapacity:count * 3];
		NSInteger trashFolderId = db.trashFolderId;
		for (index = 0; index < count; ++index)
		{
			NSInteger folderId = [arrayOfSources[index] integerValue];
			
			// Don't allow the trash folder to move under a group folder, because the group folder could get deleted.
			// Also, don't allow perverse moves.  We should probably do additional checking: not only whether the new parent
			// is the folder itself but also whether the new parent is a subfolder.
			if (((folderId == trashFolderId) && (node != self.rootNode)) || (folderId == parentId) || (folderId == predecessorId))
				continue;
			[array addObject:@(folderId)];
			[array addObject:@(parentId)];
			[array addObject:@(predecessorId)];
			predecessorId = folderId;
		}

		// Do the move
		BOOL result = [self moveFolders:array withGoogleSync:YES];
		return result;
	}
	if ([type isEqualToString:MA_PBoardType_RSSSource])
	{
		Database * dbManager = [Database sharedManager];
		NSArray * arrayOfSources = [pb propertyListForType:type];
		NSInteger count = arrayOfSources.count;
		NSInteger index;
		
		// This is an RSS drag using the protocol defined by Ranchero for NetNewsWire. See
		// http://ranchero.com/netnewswire/rssclipboard.php for more details.
		//
		__block NSInteger folderToSelect = -1;
		for (index = 0; index < count; ++index)
		{
			NSDictionary * sourceItem = arrayOfSources[index];
			NSString * feedTitle = [sourceItem valueForKey:@"sourceName"];
			NSString * feedHomePage = [sourceItem valueForKey:@"sourceHomeURL"];
			NSString * feedURL = [sourceItem valueForKey:@"sourceRSSURL"];
			NSString * feedDescription = [sourceItem valueForKey:@"sourceDescription"];

			if ((feedURL != nil) && [dbManager folderFromFeedURL:feedURL] == nil)
			{
				NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
				NSInteger folderId = [dbManager addRSSFolder:feedTitle underParent:parentId afterChild:predecessorId subscriptionURL:feedURL];
                if (feedDescription != nil) {
                    [dbManager setDescription:feedDescription forFolder:folderId];
                }
                if (feedHomePage != nil) {
                    [dbManager setHomePage:feedHomePage forFolder:folderId];
                }
                if (folderId > 0) {
					folderToSelect = folderId;
                }
				++childIndex;
			}
		}

		// If parent was a group, expand it now
		if (parentId != VNAFolderTypeRoot)
			[self.outlineView expandItem:[self.rootNode nodeFromID:parentId]];
		
		// Select a new folder
		if (folderToSelect > 0)
			[self selectFolder:folderToSelect];
		
		return YES;
	}
	if ([type isEqualToString:@"WebURLsWithTitlesPboardType"])
	{
		Database * dbManager = [Database sharedManager];
		NSArray * webURLsWithTitles = [pb propertyListForType:type];
		NSArray * arrayOfURLs = webURLsWithTitles[0];
		NSArray * arrayOfTitles = webURLsWithTitles[1];
		NSInteger count = arrayOfURLs.count;
		NSInteger index;
		
		__block NSInteger folderToSelect = -1;
		for (index = 0; index < count; ++index)
		{
			NSString * feedTitle = arrayOfTitles[index];
			NSString * feedURL = arrayOfURLs[index];
			NSURL * draggedURL = [NSURL URLWithString:feedURL];
			if ((draggedURL.scheme != nil) && [draggedURL.scheme isEqualToString:@"feed"])
				feedURL = [NSString stringWithFormat:@"http:%@", draggedURL.resourceSpecifier];
			
			if ([dbManager folderFromFeedURL:feedURL] == nil)
			{
				NSInteger predecessorId = (childIndex > 0) ? [node childByIndex:(childIndex - 1)].nodeId : 0;
				NSInteger newFolderId = [dbManager addRSSFolder:feedTitle underParent:parentId afterChild:predecessorId subscriptionURL:feedURL];
                if (newFolderId > 0) {
					folderToSelect = newFolderId;
                }
				++childIndex;
			}
		}
		
		// If parent was a group, expand it now
		if (parentId != VNAFolderTypeRoot)
			[self.outlineView expandItem:[self.rootNode nodeFromID:parentId]];
		
		// Select a new folder
		if (folderToSelect > 0)
			[self selectFolder:folderToSelect];
		
		return YES;
	}
	return NO; 
}

/* setSearch
 * Set string to filter nodes by name, description, url
 */
-(void)setSearch:(NSString *)f {
    NSString* tf = [f stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (tf.length == 0) {
        self.outlineView.filterPredicate = nil;
        return;
    }

    NSString *match = [NSString stringWithFormat:@"*%@*", tf];
    NSPredicate* predicate = [NSPredicate predicateWithFormat:@"folder.name like[cd] %@ OR folder.feedDescription like[cd] %@ OR folder.feedURL like[cd] %@", match, match, match];

    if ([self.outlineView.filterPredicate.predicateFormat isEqualToString:predicate.predicateFormat]) {
        return;
    }

    self.outlineView.filterPredicate = predicate;
}

/* dealloc
 * Clean up and release resources.
 */
-(void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
