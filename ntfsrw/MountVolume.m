//
//  MountVolume.m
//  ntfsrw
//
//  Created by German Skalauhov on 24.04.15.
//  Copyright (c) 2015 German Skalauhov. All rights reserved.
//

#import <DiskArbitration/DiskArbitration.h>
#import <Cocoa/Cocoa.h>
#include <sys/mount.h>
#import "MountVolume.h"

@implementation MountVolume


- (id)init {
    self = [super init];
    if (!self)
        return self;
    return self;
}


NSString *label;

- (NSString *)launchAgentPlistPath {
    NSURL *libUrl = [[[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] lastObject];
    return [[libUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"LaunchAgents/org.eu.grsk.ntfsrw.plist"]] path];
}

- (NSDictionary *)makeLaunchAgentPList {
    return @{@"Label": @"org.eu.grsk.ntfsrw",
             @"ProgramArguments": @[@"/usr/local/bin/ntfsrw"],
             @"RunAtLoad": @NO};
}

- (BOOL) setToLaunchAgent:(BOOL)value {
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithDictionary:[self makeLaunchAgentPList]];
    plist[@"RunAtLoad"] = @(value);
    return [plist writeToFile:[self launchAgentPlistPath] atomically:YES];
}

-(void) addPathToSharedItem:(NSString *)path
{
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];

    // Create a reference to the shared file list.
    LSSharedFileListRef favoriteItems = LSSharedFileListCreate(NULL, kLSSharedFileListFavoriteItems, NULL);
    if (favoriteItems) {
        NSLog(@"add %@ to sidebar", path);
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(favoriteItems,
                                                                     kLSSharedFileListItemLast, NULL, NULL,
                                                                     url, NULL, NULL);
        if (item) CFRelease(item);
        CFRelease(favoriteItems);
    }
}

- (void)removePathFromSharedItem:(NSString *)appPath {
    UInt32 seedValue;
    LSSharedFileListRef favoriteItems = LSSharedFileListCreate(NULL,
                                                               kLSSharedFileListFavoriteItems, NULL);
    CFArrayRef loginItemsArray = LSSharedFileListCopySnapshot(favoriteItems, &seedValue);
    for (id item in (__bridge NSArray *)loginItemsArray) {
        LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)item;
        CFStringRef itemString = LSSharedFileListItemCopyDisplayName(itemRef);
        if ([(__bridge NSString *)itemString isEqualToString:appPath]) {
            NSLog(@"delete item %@",itemString);
            LSSharedFileListItemRemove(favoriteItems, itemRef); // Deleting the item
        }
        if(itemString) CFRelease(itemString);
    }
    if (loginItemsArray) CFRelease(loginItemsArray);
    if (favoriteItems) CFRelease(favoriteItems);
}

void mount_done(DADiskRef disk, DADissenterRef dissenter, void *context)
{
    if (dissenter) {
        NSLog(@"mount error");
    } else {
        NSLog(@"mount done");
    }
}

void unmount_done(DADiskRef disk, DADissenterRef dissenter, void *context)
{
    if (dissenter) {
        NSLog(@"unmount error");
    } else {
        NSLog(@"unmount done");
        NSDictionary *error = [NSDictionary new];
        NSString *shellCmd = [NSString stringWithFormat:@"echo 'LABEL=%@ none ntfs rw,auto,nobrowse' >> /etc/fstab", label];
        NSLog(@"shellCmd %@", shellCmd);
        NSString *script =  [NSString  stringWithFormat:@"do shell script \"%@\" with administrator privileges", shellCmd];;
        NSAppleScript *appleScript = [[NSAppleScript new] initWithSource:script];
        if ([appleScript executeAndReturnError:&error]) {
            NSLog(@"update fstab");
        } else {
            NSLog(@"Unable to access fstab");
            return;
        }
        DASessionRef session = DASessionCreate(kCFAllocatorDefault);
        DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        DADiskMount(disk, NULL, kDADiskMountOptionDefault, mount_done, NULL);
        if (session) {CFRelease(session);}
    }
}

- (void) volumeListDidChange:(NSNotification *)notification {
    NSString *mountToName = [[notification userInfo] objectForKey:@"NSDevicePath"];
    label = [[notification userInfo] objectForKey:@"NSWorkspaceVolumeLocalizedNameKey"];

    NSLog(@"notification for %@ label %@", mountToName, label);

    if ( notification.name == NSWorkspaceDidMountNotification) {
        struct statfs buffer;
        int returnCode = statfs( [mountToName fileSystemRepresentation], &buffer);
        if ( returnCode == 0 ) {
            NSLog(@"Mount From: %s to Path: %s File System Type: %s with flags %d",
                  buffer.f_mntfromname, buffer.f_mntonname, buffer.f_fstypename, buffer.f_flags);

            if ( strcasecmp(buffer.f_fstypename, "ntfs") == 0 ) {
                if (buffer.f_flags&MNT_RDONLY ) {
                    NSLog(@"Try remount rw");

                    CFAllocatorRef allocator = kCFAllocatorDefault;
                    DASessionRef session = DASessionCreate(kCFAllocatorDefault);
                    NSLog(@"Unmount volume %s at %s", buffer.f_mntfromname, buffer.f_mntonname);

                    DADiskRef disk = DADiskCreateFromBSDName(allocator, session, buffer.f_mntfromname);
                    if (disk) {
                        NSLog(@"Got disk...");
                        DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);

                        DADiskUnmount(disk, kDADiskMountOptionDefault, unmount_done, NULL);
                        CFRelease(disk);
                    }
                    if (session) CFRelease(session);
                }
                else {
                    [self addPathToSharedItem:mountToName];
                }
            }
        }
    }
    else if (notification.name == NSWorkspaceDidUnmountNotification) {
        [self removePathFromSharedItem:label];
    }
}

- (void)start {
    [self setToLaunchAgent:YES];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(volumeListDidChange:) name:NSWorkspaceDidMountNotification object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(volumeListDidChange:) name:NSWorkspaceDidUnmountNotification object:nil];
    return;
}

@end
