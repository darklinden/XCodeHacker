
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stdlib.h>
#include <stdio.h>
#include <pwd.h>
#include <unistd.h>

//-f "/Users/apple2/Desktop/1.mobileprovision" -p "/Users/apple2/Desktop/iZip/iZip.xcodeproj" -s "iPhone Distribution: Comc Soft Corporation"

static NSString *getUUID(NSString *path_provision_profile)
{
    //get uuid
    NSString *kUUID = @"UUID";
    NSString *str_uuid = nil;
    CMSDecoderRef decoder = NULL;
    CFDataRef dataRef = NULL;
    NSString *plistString = nil;
    
    @try {
        CMSDecoderCreate(&decoder);
        NSData *fileData = [NSData dataWithContentsOfFile:path_provision_profile];
        CMSDecoderUpdateMessage(decoder, fileData.bytes, fileData.length);
        CMSDecoderFinalizeMessage(decoder);
        CMSDecoderCopyContent(decoder, &dataRef);
        plistString = [[NSString alloc] initWithData:(__bridge NSData *)dataRef encoding:NSUTF8StringEncoding];
    }
    @catch (NSException *exception) {
        @throw exception;
    }
    @finally {
        if (decoder) CFRelease(decoder);
        if (dataRef) CFRelease(dataRef);
    }
    
    if (plistString) {
        NSDictionary *plist = [plistString propertyList];
        
        id result = [plist valueForKeyPath:kUUID];
        if (result) {
            if ([result isKindOfClass:[NSArray class]] && [result count]) {
                str_uuid = [result componentsJoinedByString:@"\n"];
            }
            else {
                str_uuid = [result description];
            }
        }
    }
    
    if (!str_uuid) {
        printf("XcodeHacker: provision profile get uuid failed.\n");
    }
    
    return str_uuid;
}

static NSString *getSettingPath(NSString *path_project)
{
    //open project file
    NSFileManager *fmgr = [NSFileManager defaultManager];
    
    if (![fmgr fileExistsAtPath:path_project]) {
        printf("XcodeHacker: no file found at %s! \n", path_project.UTF8String);
        return nil;
    }
    
    NSError *error = nil;
    NSArray *pArr_content = [fmgr contentsOfDirectoryAtPath:path_project error:&error];
    if (error) {
        printf("XcodeHacker: open project file err:%s \n", error.description.UTF8String);
        return nil;
    }
    
    //get build settings
    NSString *path_build_settings = nil;
    
    for (NSString *str_file_name in pArr_content) {
        if ([str_file_name.pathExtension.lowercaseString isEqualToString:@"pbxproj"]) {
            path_build_settings = [path_project stringByAppendingPathComponent:str_file_name];
            break;
        }
    }
    
    if (!path_build_settings) {
        printf("XcodeHacker: there's no build setting file in project:%s \n", path_project.UTF8String);
        return nil;
    }
    
    return path_build_settings;
}

static NSMutableDictionary *getSettingsContent(NSString *path_build_settings)
{
    NSError *error = nil;
    NSString *str_settings_content = [NSString stringWithContentsOfFile:path_build_settings
                                                               encoding:NSUTF8StringEncoding
                                                                  error:&error];
    if (error) {
        printf("XcodeHacker: open setting file failed:%s \n", path_build_settings.UTF8String);
        return nil;
    }
    
    NSDictionary *pDict_build_settings = [str_settings_content propertyList];
    if (!pDict_build_settings) {
        printf("XcodeHacker: get setting file content plist failed:%s \n", path_build_settings.UTF8String);
        return nil;
    }
    
    printf("XcodeHacker: get setting file content plist success! \n");
    
    return [NSMutableDictionary dictionaryWithDictionary:pDict_build_settings];
}

static NSMutableArray *replaceSignAndReturnPlist(NSMutableDictionary **dict_settings, NSString *str_sign, NSString *str_profile)
{
    BOOL success = NO;
    NSArray *pArr_keys = (*dict_settings).allKeys;
    NSDictionary *pDict_objs = [*dict_settings objectForKey:@"objects"];
    NSMutableDictionary *pDict_change_obj = [NSMutableDictionary dictionaryWithDictionary:pDict_objs];
    pArr_keys = pDict_change_obj.allKeys;
    NSMutableArray *pArr_plist = [NSMutableArray array];
    
    for (NSString *key in pArr_keys) {
        NSDictionary *pDict_tmp = [pDict_change_obj objectForKey:key];
        NSArray *pArr_tmp = pDict_tmp.allKeys;
        if ([pArr_tmp containsObject:@"buildSettings"]) {
            NSMutableDictionary *pDict_setting_parent = [NSMutableDictionary dictionaryWithDictionary:pDict_tmp];
            NSMutableDictionary *pDict_setting = [NSMutableDictionary dictionaryWithDictionary:[pDict_setting_parent objectForKey:@"buildSettings"]];
            NSString *str_plist = [pDict_setting objectForKey:@"INFOPLIST_FILE"];
            if (str_plist) {
                if (![pArr_plist containsObject:str_plist]) {
                    [pArr_plist addObject:str_plist];
                }
            }
            [pDict_setting setObject:str_sign forKey:@"CODE_SIGN_IDENTITY"];
            [pDict_setting setObject:str_sign forKey:@"CODE_SIGN_IDENTITY[sdk=iphoneos*]"];
            [pDict_setting setObject:str_profile forKey:@"PROVISIONING_PROFILE"];
            [pDict_setting setObject:str_profile forKey:@"PROVISIONING_PROFILE[sdk=iphoneos*]"];
            [pDict_setting_parent setObject:pDict_setting forKey:@"buildSettings"];
            [pDict_change_obj setObject:pDict_setting_parent forKey:key];
            success = YES;
        }
//        //hard code remove runscript
//        if ([pArr_tmp containsObject:@"shellScript"]) {
//            NSString *pStr_script = [pDict_tmp objectForKey:@"shellScript"];
//            if (pStr_script) {
//                printf("XcodeHacker: remove shellScript :[%s]!\n", pStr_script.UTF8String);
//            }
//            [pDict_change_obj removeObjectForKey:key];
//        }
    }
    
    if (success) {
        printf("XcodeHacker: code sign changed success! \n");
    }
    
    [*dict_settings setObject:pDict_change_obj forKey:@"objects"];
    
    return pArr_plist;
}

static NSMutableArray *getPlistPaths(NSString *folder, NSArray *array_plist)
{
    NSFileManager *fmgr = [NSFileManager defaultManager];
    NSMutableArray *pArr_plist = [NSMutableArray array];
    NSArray *pArr_file_name = [fmgr contentsOfDirectoryAtPath:folder error:nil];
    for (NSString *str_file_name in pArr_file_name) {
        NSString *path_tmp_file = [folder stringByAppendingPathComponent:str_file_name];
        BOOL bool_file_is_directory = NO;
        BOOL bool_file_exist = [fmgr fileExistsAtPath:path_tmp_file isDirectory:&bool_file_is_directory];
        if (bool_file_exist) {
            if (bool_file_is_directory) {
                [pArr_plist addObjectsFromArray:getPlistPaths(path_tmp_file, array_plist)];
            }
            else {
                if ([path_tmp_file.pathExtension.lowercaseString isEqualToString:@"plist"]) {
                    for (NSString *str_info_plist in array_plist) {
                        if ([path_tmp_file.lastPathComponent.lowercaseString isEqualToString:str_info_plist.lastPathComponent.lowercaseString]) {
                            [pArr_plist addObject:path_tmp_file];
                            break;
                        }
                    }
                }
            }
        }
    }
    return pArr_plist;
}

static void setupBuildVersion(NSString *path_project, NSArray *array_plist)
{
    NSString *path_project_parent = [path_project stringByDeletingLastPathComponent];
    NSArray *pArr_plist = getPlistPaths(path_project_parent, array_plist);
    for (NSString *path_plist in pArr_plist) {
        printf("XcodeHacker: get project plist path :[%s]\n", path_plist.UTF8String);
        NSString *str_plist_content = [NSString stringWithContentsOfFile:path_plist encoding:NSUTF8StringEncoding error:nil];
        NSDictionary *pDict_plist = [str_plist_content propertyList];
        if (pDict_plist) {
            NSMutableDictionary *pDict_change_version = [NSMutableDictionary dictionaryWithDictionary:pDict_plist];
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
            NSString *str_ver = [dateFormatter stringFromDate:[NSDate date]];
            [pDict_change_version setObject:str_ver forKey:@"CFBundleVersion"];
            
            NSFileManager *fmgr = [NSFileManager defaultManager];
            [fmgr removeItemAtPath:path_plist error:nil];
            
            if (![pDict_change_version writeToFile:path_plist atomically:YES]) {
                printf("XcodeHacker: save plist file [%s] failed.\n", path_plist.UTF8String);
            }
            else {
                printf("XcodeHacker: save plist file [%s] success.\n", path_plist.UTF8String);
            }
        }
    }
}

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        
        NSUserDefaults *arguments = [NSUserDefaults standardUserDefaults];
        NSString *path_provision_profile = [arguments stringForKey:@"f"];
        NSString *path_project = [arguments stringForKey:@"p"];
        NSString *key_code_sign = [arguments stringForKey:@"s"];
        
        if (path_provision_profile && path_project && key_code_sign) {
            
            NSString *str_uuid = getUUID(path_provision_profile);
            
            if (!str_uuid) {
                return -1;
            }
            
            printf("XcodeHacker: provision profile get uuid:[%s] \n", str_uuid.UTF8String);
            
            NSString *path_build_settings = getSettingPath(path_project);
            
            if (!path_build_settings) {
                return -1;
            }
            
            printf("XcodeHacker: get build setting file path:[%s] \n", path_build_settings.UTF8String);
            
            NSMutableDictionary *pDict_settings = getSettingsContent(path_build_settings);
            
            if (!pDict_settings) {
                return -1;
            }
            
            NSArray *pArr_plist = replaceSignAndReturnPlist(&pDict_settings, key_code_sign, str_uuid);
            
            NSFileManager *fmgr = [NSFileManager defaultManager];
            NSError *err = nil;
            [fmgr removeItemAtPath:path_build_settings error:&err];
            if (err) {
                printf("XcodeHacker: remove old settings file failed! error:%s \n", err.description.UTF8String);
                return -1;
            }
            
            if (![pDict_settings writeToFile:path_build_settings atomically:YES]) {
                printf("XcodeHacker: save new settings file failed.\n");
            }
            else {
                printf("XcodeHacker: save new settings file success.\n");
            }
            
            const char *homeDir = getenv("HOME");
            
            if (!homeDir) {
                struct passwd* pwd = getpwuid(getuid());
                if (pwd)
                    homeDir = pwd->pw_dir;
            }
            
            NSString *path_profile_des = [NSString stringWithFormat:@"%s/Library/MobileDevice/Provisioning Profiles/%@.mobileprovision", homeDir, str_uuid];
            err = nil;
            [fmgr copyItemAtPath:path_provision_profile toPath:path_profile_des error:&err];
            if (err) {
                printf("XcodeHacker: copy profile err:[%s]. \n", err.localizedFailureReason.UTF8String);
            }
            
            setupBuildVersion(path_project, pArr_plist);
        }
        else {
            printf("XcodeHacker: xcode project hack param error! \n");
            return -1;
        }
    }
    return 0;
}

