//
//  EigenWrapper.mm
//  OpticALLY
//
//  Created by John Seong on 5/8/24.
//

#import "Eigen/Core"
#import "EigenWrapper.h"

@implementation EigenWrapper

+ (NSString *)eigenVersionString {
    return [NSString stringWithFormat:@"Eigen Version %d.%d.%d", EIGEN_WORLD_VERSION, EIGEN_MAJOR_VERSION, EIGEN_MINOR_VERSION];
}

@end
