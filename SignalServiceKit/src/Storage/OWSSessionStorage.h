//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSStorage.h"

NS_ASSUME_NONNULL_BEGIN

// TODO: Close database in background.
// TODO: Use background task around transactions.
@interface OWSSessionStorage : OWSStorage

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedManager;

- (YapDatabaseConnection *)dbConnection;
+ (YapDatabaseConnection *)dbConnection;

+ (NSString *)databaseFilePath;
+ (NSString *)databaseFilePath_SHM;
+ (NSString *)databaseFilePath_WAL;

@end

NS_ASSUME_NONNULL_END
