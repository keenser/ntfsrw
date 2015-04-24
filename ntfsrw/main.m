//
//  main.m
//  ntfsrw
//
//  Created by German Skalauhov on 23.04.15.
//  Copyright (c) 2015 German Skalauhov. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MountVolume.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        MountVolume *source = [[MountVolume alloc] init];
        [source start];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
