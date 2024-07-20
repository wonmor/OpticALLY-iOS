//
//  DlibWrapperDelegate.h
//  DisplayLiveSamples
//
//  Created by Stanley Chiang on 8/11/16.
//  Copyright © 2016 ZweiGraf. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DlibWrapper;

@protocol DlibWrapperDelegate <NSObject>

-(void) mouthVerticePositions:(NSMutableArray *)vertices;

@end