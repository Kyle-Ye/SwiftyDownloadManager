#import <Foundation/Foundation.h>

#include "SDMFileFinalizer.h"

#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <string>
#include <sys/stdio.h>

namespace {

std::string error_description(NSError *error) {
    if (error == nil) {
        return "The destination could not be written.";
    }
    const auto *description = error.localizedDescription.UTF8String;
    return description == nullptr
        ? "The destination could not be written."
        : std::string(description);
}

NSError *file_exists_error(NSURL *destination) {
    return [NSError errorWithDomain:NSCocoaErrorDomain
                               code:NSFileWriteFileExistsError
                           userInfo:@{NSFilePathErrorKey: destination.path}];
}

bool exclusive_rename(NSURL *source, NSURL *destination, NSError **error) {
    if (::renameatx_np(
            AT_FDCWD,
            source.fileSystemRepresentation,
            AT_FDCWD,
            destination.fileSystemRepresentation,
            RENAME_EXCL
        ) == 0) {
        return true;
    }

    const auto error_code = errno;
    if (error != nullptr) {
        *error = error_code == EEXIST
            ? file_exists_error(destination)
            : [NSError errorWithDomain:NSPOSIXErrorDomain
                                   code:error_code
                               userInfo:@{NSFilePathErrorKey: destination.path}];
    }
    return false;
}

bool synchronize_file(NSURL *url, NSError **error) {
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingToURL:url error:error];
    if (handle == nil) {
        return false;
    }
    const auto synchronized = [handle synchronizeAndReturnError:error];
    NSError *close_error = nil;
    const auto closed = [handle closeAndReturnError:&close_error];
    if (!synchronized) {
        return false;
    }
    if (!closed) {
        if (error != nullptr) {
            *error = close_error;
        }
        return false;
    }
    return true;
}

} // namespace

namespace sdm {

bool finalize_file(
    const std::filesystem::path &source,
    const std::filesystem::path &destination,
    bool replaces_existing,
    std::string &error_message
) noexcept {
    @autoreleasepool {
        @try {
            const auto source_string = source.string();
            const auto destination_string = destination.string();
            NSString *source_path = [NSString stringWithUTF8String:source_string.c_str()];
            NSString *destination_path = [NSString
                stringWithUTF8String:destination_string.c_str()];
            if (source_path == nil || destination_path == nil) {
                error_message = "The source or destination path is not valid UTF-8.";
                return false;
            }

            NSURL *source_url = [NSURL fileURLWithPath:source_path isDirectory:NO];
            NSURL *destination_url = [NSURL
                fileURLWithPath:destination_path
                isDirectory:NO];
            NSFileCoordinator *coordinator = [[NSFileCoordinator alloc]
                initWithFilePresenter:nil];
            __block NSError *operation_error = nil;
            __block bool completed = false;
            NSError *coordination_error = nil;
            const auto writing_options = replaces_existing
                ? NSFileCoordinatorWritingForReplacing
                : static_cast<NSFileCoordinatorWritingOptions>(0);

            [coordinator
                coordinateReadingItemAtURL:source_url
                options:NSFileCoordinatorReadingWithoutChanges
                writingItemAtURL:destination_url
                options:writing_options
                error:&coordination_error
                byAccessor:^(NSURL *coordinated_source, NSURL *coordinated_destination) {
                    NSFileManager *file_manager = [[NSFileManager alloc] init];
                    const auto destination_exists = [file_manager
                        fileExistsAtPath:coordinated_destination.path];
                    if (destination_exists && !replaces_existing) {
                        operation_error = file_exists_error(coordinated_destination);
                        return;
                    }

                    if (replaces_existing) {
                        if (::rename(
                                coordinated_source.fileSystemRepresentation,
                                coordinated_destination.fileSystemRepresentation
                            ) == 0) {
                            completed = true;
                            return;
                        }
                    } else {
                        if (exclusive_rename(
                                coordinated_source,
                                coordinated_destination,
                                &operation_error
                            )) {
                            completed = true;
                            return;
                        }
                        if ([operation_error.domain isEqualToString:NSCocoaErrorDomain] &&
                            operation_error.code == NSFileWriteFileExistsError) {
                            return;
                        }
                    }

                    NSURL *destination_directory = coordinated_destination
                        .URLByDeletingLastPathComponent;
                    NSString *staging_name = [NSString stringWithFormat:
                        @".%@.%@.sdm-export",
                        coordinated_destination.lastPathComponent,
                        NSUUID.UUID.UUIDString];
                    NSURL *staging_url = [destination_directory
                        URLByAppendingPathComponent:staging_name
                        isDirectory:NO];

                    if (![file_manager
                            copyItemAtURL:coordinated_source
                            toURL:staging_url
                            error:&operation_error]) {
                        return;
                    }
                    if (!synchronize_file(staging_url, &operation_error)) {
                        [file_manager removeItemAtURL:staging_url error:nil];
                        return;
                    }

                    if (!replaces_existing) {
                        if (!exclusive_rename(
                                staging_url,
                                coordinated_destination,
                                &operation_error
                            )) {
                            [file_manager removeItemAtURL:staging_url error:nil];
                            return;
                        }
                    } else {
                        const auto coordinated_destination_exists = [file_manager
                            fileExistsAtPath:coordinated_destination.path];
                        if (coordinated_destination_exists) {
                            if (![file_manager
                                    replaceItemAtURL:coordinated_destination
                                    withItemAtURL:staging_url
                                    backupItemName:nil
                                    options:0
                                    resultingItemURL:nil
                                    error:&operation_error]) {
                                [file_manager removeItemAtURL:staging_url error:nil];
                                return;
                            }
                        } else if (![file_manager
                                       moveItemAtURL:staging_url
                                       toURL:coordinated_destination
                                       error:&operation_error]) {
                            [file_manager removeItemAtURL:staging_url error:nil];
                            return;
                        }
                    }

                    // The destination is committed at this point, so a sandbox
                    // cleanup failure must not turn a successful save into a retry.
                    [file_manager removeItemAtURL:coordinated_source error:nil];
                    completed = true;
                }];

            if (completed) {
                error_message.clear();
                return true;
            }
            error_message = error_description(
                coordination_error == nil ? operation_error : coordination_error
            );
            return false;
        } @catch (NSException *exception) {
            const auto *reason = exception.reason.UTF8String;
            error_message = reason == nullptr
                ? "File coordination failed."
                : std::string(reason);
            return false;
        }
    }
}

} // namespace sdm
