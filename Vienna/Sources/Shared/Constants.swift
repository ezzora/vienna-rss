//
//  Constants.swift
//  Vienna
//
//  Copyright 2019
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

@objc
enum MAFilterMode: Int {
    case
    all = 0,
    unread = 1,
    lastRefresh = 2,
    today = 3,
    last48h = 4,
    flagged = 5,
    unreadOrFlagged = 6
}

@objc
enum MALayout: Int {
    case
    report = 1,
    condensed = 2,
    unified = 3
}

@objc
enum MAEmptyTrash: Int {
    case
    none = 0,
    withoutWarning = 1,
    withWarning = 2
}

@objc
enum MAFolderSort: Int {
    case
    manual = 0,
    byName = 1
}

@objc
enum MARefresh: Int {
    case
    redrawList = 0,
    reapplyFilter = 1,
    sortAndRedraw = 3
}

/// New articles notification method (managed as an array of binary flags)
@objc
enum MANewArticlesNotification: Int {
    case
    badge = 1,
    bounce = 2
}
