//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSDatabaseMigrationRunner.h"
#import "OWS100RemoveTSRecipientsMigration.h"
#import "OWS102MoveLoggingPreferenceToUserDefaults.h"
#import "OWS103EnableVideoCalling.h"
#import "OWS104CreateRecipientIdentities.h"
#import "OWS105AttachmentFilePaths.h"
#import "OWS107LegacySounds.h"
#import "OWS108CallLoggingPreference.h"
#import "OWS109OutgoingMessageState.h"
#import "OWSDatabaseMigration.h"
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

@implementation OWSDatabaseMigrationRunner

#pragma mark - Dependencies

- (OWSPrimaryStorage *)primaryStorage
{
    OWSAssertDebug(SSKEnvironment.shared.primaryStorage);

    return SSKEnvironment.shared.primaryStorage;
}

#pragma mark -

// This should all migrations which do NOT qualify as safeBlockingMigrations:
- (NSArray<OWSDatabaseMigration *> *)allMigrations
{
    NSArray<OWSDatabaseMigration *> *prodMigrations = @[
        [[OWS100RemoveTSRecipientsMigration alloc] init],
        [[OWS102MoveLoggingPreferenceToUserDefaults alloc] init],
        [[OWS103EnableVideoCalling alloc] init],
        [[OWS104CreateRecipientIdentities alloc] init],
        [[OWS105AttachmentFilePaths alloc] init],
        [[OWS106EnsureProfileComplete alloc] init],
        [[OWS107LegacySounds alloc] init],
        [[OWS108CallLoggingPreference alloc] init],
        [[OWS109OutgoingMessageState alloc] init],
        [OWS110SortIdMigration new],
        [[OWS111UDAttributesMigration alloc] init],
        [[OWS112TypingIndicatorsMigration alloc] init],
        [[OWS113MultiAttachmentMediaMessages alloc] init],
        [[OWS114RemoveDynamicInteractions alloc] init],
        [OWS115EnsureProfileAvatars new]
    ];

    if (SSKFeatureFlags.useGRDB) {
        return [prodMigrations arrayByAddingObjectsFromArray:@ [[OWS1XXGRDBMigration new]]];
    } else {
        return prodMigrations;
    }
}

// GRDB TODO: Make sure this makes sense in the following scenarios:
//
// * Without YDB-to-GRDB migration (YDB before GRDB enabled).
// * Before YDB-to-GRDB migration.
// * After YDB-to-GRDB migration.
// * Without YDB-to-GRDB migration (New GRDB-only install).
- (void)assumeAllExistingMigrationsRun
{
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        OWSLogInfo(@"Skipping migration on new install: %@", migration);
        [migration markAsCompleteWithSneakyTransaction];
    }
}

- (void)runAllOutstandingWithCompletion:(OWSDatabaseMigrationCompletion)completion
{
    [self removeUnknownMigrations];

    [self runMigrations:[self.allMigrations mutableCopy] completion:completion];
}

// Some users (especially internal users) will move back and forth between
// app versions.  Whenever they move "forward" in the version history, we
// want them to re-run any new migrations. Therefore, when they move "backward"
// in the version history, we cull any unknown migrations.
//
// GRDB TODO: Make sure this makes sense in the following scenarios:
//
// * Without YDB-to-GRDB migration (YDB before GRDB enabled).
//   Migrations should run, reading/writing to YDB.
// * During YDB-to-GRDB migration.
//   Migrations should run.
//   YDB migrations should consult YDB.
//   GRDB migrations should consult GRDB.
// * Without YDB-to-GRDB migration (New GRDB-only install).
//   Migrations should not be run.
//   All migrations should be marked as complete in GRDB.
- (void)removeUnknownMigrations
{
    NSMutableSet<NSString *> *knownMigrationIds = [NSMutableSet new];
    for (OWSDatabaseMigration *migration in self.allMigrations) {
        [knownMigrationIds addObject:migration.migrationId];
    }

    [self.primaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSArray<NSString *> *savedMigrationIds =
            [OWSDatabaseMigration allCompleteMigrationIdsWithTransaction:transaction.asAnyRead];

        NSMutableSet<NSString *> *unknownMigrationIds = [NSMutableSet new];
        [unknownMigrationIds addObjectsFromArray:savedMigrationIds];
        [unknownMigrationIds minusSet:knownMigrationIds];

        for (NSString *unknownMigrationId in unknownMigrationIds) {
            OWSLogInfo(@"Culling unknown migration: %@", unknownMigrationId);
            [OWSDatabaseMigration markMigrationIdAsIncomplete:unknownMigrationId transaction:transaction.asAnyWrite];
        }
    }];
}

// Run migrations serially to:
//
// * Ensure predictable ordering.
// * Prevent them from interfering with each other (e.g. deadlock).
- (void)runMigrations:(NSMutableArray<OWSDatabaseMigration *> *)migrations
           completion:(OWSDatabaseMigrationCompletion)completion
{
    OWSAssertDebug(migrations);
    OWSAssertDebug(completion);

    // If there are no more migrations to run, complete.
    if (migrations.count < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
        return;
    }

    // Pop next migration from front of queue.
    OWSDatabaseMigration *migration = migrations.firstObject;
    [migrations removeObjectAtIndex:0];

    // If migration has already been run, skip it.
    if (migration.isCompleteWithSneakyTransaction) {
        [self runMigrations:migrations completion:completion];
        return;
    }

    OWSLogInfo(@"Running migration: %@ %@", migration, migration.migrationId);

    [migration runUpWithCompletion:^{
        OWSLogInfo(@"Migration complete: %@ %@", migration, migration.migrationId);

        [self runMigrations:migrations completion:completion];
    }];
}

@end

NS_ASSUME_NONNULL_END
