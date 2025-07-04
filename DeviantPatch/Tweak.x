// By LakeTakeCake
// 2025 4 Jul

#import <objc/runtime.h>
#import <Foundation/Foundation.h>

@interface DVNTCredential : NSObject
@property (nonatomic, strong) NSString *accessToken;
@property (nonatomic, strong) NSString *refreshToken;
@property (nonatomic, strong) NSDate *expiration;
@property (nonatomic, assign) NSInteger tokenType;
+ (instancetype)createCredentialWithAccessToken:(NSString *)accessToken tokenType:(NSInteger)tokenType;
@end

%hook DVNTSettingsTableViewController
+ (int)logout {
    // NSLog(@"[Hook] Intercepted logout. Clearing saved token.");

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"MyAccessToken"];
    [defaults removeObjectForKey:@"MyRefreshToken"];
    [defaults removeObjectForKey:@"MyTokenExpiry"];
    [defaults synchronize];

    return %orig;
}
%end

%hook DVNTCredential
+ (instancetype)retrieveCredentialForTokenType:(NSInteger)type withIdentifier:(id)identifier {
    // NSLog(@"[Hook] Intercepting credential retrieval for type: %ld identifier: %@", (long)type, identifier);

    NSString *accessToken = [[NSUserDefaults standardUserDefaults] stringForKey:@"MyAccessToken"];
    NSString *refreshToken = [[NSUserDefaults standardUserDefaults] stringForKey:@"MyRefreshToken"];
    NSTimeInterval expiry = [[NSUserDefaults standardUserDefaults] doubleForKey:@"MyTokenExpiry"];

    if (accessToken) {
        // NSLog(@"[Hook] Reconstructing DVNTCredential with saved access token");
        DVNTCredential *credential = [self createCredentialWithAccessToken:accessToken tokenType:type];
        [credential setRefreshToken:refreshToken];
        [credential setExpiration:[NSDate dateWithTimeIntervalSince1970:expiry]];
        return credential;
    }

    return %orig(type, identifier);
}
%end

%hook AFHTTPSessionManager
- (NSURLSessionDataTask *)POST:(NSString *)URLString
                     parameters:(id)parameters
                        headers:(NSDictionary *)headers
                       progress:(void (^)(NSProgress *uploadProgress))uploadProgress
                        success:(void (^)(NSURLSessionDataTask *task, id responseObject))success
                        failure:(void (^)(NSURLSessionDataTask *task, NSError *error))failure {

    // NSLog(@"[Hook] Intercepted POST: %@", URLString);
    // NSLog(@"[Hook] Parameters: %@", parameters);

    void (^wrappedSuccess)(NSURLSessionDataTask *, id) = ^(NSURLSessionDataTask *task, id responseObject) {

        // NSLog(@"[Hook] AFHTTPSessionManager Response: %@", responseObject);

        if ([responseObject isKindOfClass:[NSDictionary class]]) {
            NSDictionary *json = (NSDictionary *)responseObject;
            NSString *accessToken = json[@"access_token"];
            NSString *scope = json[@"scope"];
            NSNumber *expires = json[@"expires_in"];
            NSString *refreshToken = json[@"refresh_token"];

            if (scope) {
                // NSLog(@"[Hook] Saving access token because scope key exists: %@", accessToken);

                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                if (accessToken) {
                    [defaults setObject:accessToken forKey:@"MyAccessToken"];
                }
                if (refreshToken) {
                    [defaults setObject:refreshToken forKey:@"MyRefreshToken"];
                }
                if (expires) {
                    [defaults setDouble:[[NSDate date] timeIntervalSince1970] + [expires doubleValue] forKey:@"MyTokenExpiry"];
                }
                [defaults synchronize];
            } else {
                // NSLog(@"[Hook] Token not saved. No scope key found.");
            }
        }

        if (success) success(task, responseObject);
    };

    return %orig(URLString, parameters, headers, uploadProgress, wrappedSuccess, failure);
}
%end


id safeObjectForKeyedSubscript(id self, SEL _cmd, id key) {
    // NSLog(@"[Hook] __NSArray0 was sent objectForKeyedSubscript:, key: %@", key);

    // Check if this NSArray has any dictionaries inside (though __NSArray0 is empty)
    if ([self isKindOfClass:[NSArray class]]) {
        NSArray *arr = (NSArray *)self;
        if (arr.count > 0 && [arr[0] isKindOfClass:[NSDictionary class]]) {
            return arr[0][key];  // Try to return the value from the first dictionary
        }
    }

    // NSLog(@"[Hook] Array is empty or invalid. Returning nil");
    return nil;  // Fallback
}

%ctor { 
    Class array0Class = objc_getClass("__NSArray0");
    SEL selector = @selector(objectForKeyedSubscript:);
    Method existingMethod = class_getInstanceMethod(array0Class, selector);

    if (!existingMethod) {
        BOOL success = class_addMethod(array0Class, selector, (IMP)safeObjectForKeyedSubscript, "@@:@");
        if (success) {
            // NSLog(@"[Hook] Successfully added objectForKeyedSubscript: to __NSArray0");
        } else {
            // NSLog(@"[Hook] Failed to add objectForKeyedSubscript: to __NSArray0");
        }
    }
}
