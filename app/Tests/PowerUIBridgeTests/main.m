// Boundary tests run in an isolated process with fake Objective-C clients.
// Including the implementation keeps validation helpers private in production.
#include "../../Sources/CMacCarePowerUI/PowerUI.m"
#include <stdio.h>
#include <stdlib.h>

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "PowerUI boundary test failed at line %d\n", __LINE__); exit(1); } } while (0)

@interface FakeNativeClient : NSObject <MacCarePowerUIClient>
@property(nonatomic, copy) NSArray *values;
@property(nonatomic) unsigned char limit;
@property(nonatomic) unsigned long long enabled;
@property(nonatomic) BOOL readError;
@property(nonatomic) BOOL tornRead;
@property(nonatomic) NSUInteger limitReads;
@property(nonatomic) NSUInteger setterCalls;
@property(nonatomic) NSUInteger enabledReads;
@property(nonatomic) BOOL tornEnabledRead;
@end

@implementation FakeNativeClient
- (instancetype)initWithClientName:(NSString *)name { (void)name; return [self init]; }
- (BOOL)isMCLSupported { return YES; }
- (unsigned char)getMCLLimitWithError:(NSError **)error {
    self.limitReads++;
    if (self.readError) *error = [NSError errorWithDomain:@"MacCareBoundaryTest" code:1 userInfo:nil];
    return self.tornRead && self.limitReads > 1 ? self.limit + 5 : self.limit;
}
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error {
    self.enabledReads++;
    if (self.readError) *error = [NSError errorWithDomain:@"MacCareBoundaryTest" code:2 userInfo:nil];
    return self.tornEnabledRead && self.enabledReads > 1 ? !self.enabled : self.enabled;
}
- (NSArray *)availableChargeLimitsWithError:(NSError **)error { (void)error; return self.values; }
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error {
    (void)limit; (void)error;
    self.setterCalls++;
    return NO;
}
- (BOOL)enableMCL:(NSError **)error { (void)error; self.setterCalls++; self.enabled = 1; return YES; }
- (BOOL)disableMCL:(NSError **)error { (void)error; self.setterCalls++; self.enabled = 0; return YES; }
@end

static FakeNativeClient *fake(void) {
    FakeNativeClient *client = [FakeNativeClient new];
    client.values = @[@80, @85, @90, @95, @100];
    client.limit = 100;
    client.enabled = 0;
    return client;
}

int main(void) {
    @autoreleasepool {
        CHECK(validInterface([FakeNativeClient class]));
        Class wrong = objc_allocateClassPair([FakeNativeClient class], "MacCarePowerUIWrongReturnABI", 0);
        CHECK(wrong != Nil);
        CHECK(class_addMethod(wrong, @selector(isMCLCurrentlyEnabled:),
                              class_getMethodImplementation([FakeNativeClient class], @selector(isMCLCurrentlyEnabled:)),
                              "B24@0:8^@16"));
        objc_registerClassPair(wrong);
        CHECK(!validInterface(wrong));

        Class wrongArgument = objc_allocateClassPair([FakeNativeClient class], "MacCarePowerUIWrongArgumentABI", 0);
        CHECK(wrongArgument != Nil);
        CHECK(class_addMethod(wrongArgument, @selector(setMCLLimit:error:),
                              class_getMethodImplementation([FakeNativeClient class], @selector(setMCLLimit:error:)),
                              "B28@0:8Q16^@24"));
        objc_registerClassPair(wrongArgument);
        CHECK(!validInterface(wrongArgument));

        CHECK(validPolicyInterface([FakeNativeClient class]));
        Class wrongPolicy = objc_allocateClassPair([FakeNativeClient class], "MacCarePowerUIWrongPolicyABI", 0);
        CHECK(wrongPolicy != Nil);
        CHECK(class_addMethod(wrongPolicy, @selector(enableMCL:),
                              class_getMethodImplementation([FakeNativeClient class], @selector(enableMCL:)),
                              "Q24@0:8^@16"));
        objc_registerClassPair(wrongPolicy);
        CHECK(!validPolicyInterface(wrongPolicy));

        unsigned long long enabled = 42;
        FakeNativeClient *policyClient = fake();
        CHECK(readEnabled(policyClient, &enabled) == MACCARE_POWERUI_SUCCESS && enabled == 0);
        policyClient = fake(); policyClient.enabled = 1;
        CHECK(readEnabled(policyClient, &enabled) == MACCARE_POWERUI_SUCCESS && enabled == 1);
        policyClient = fake(); policyClient.enabled = 2;
        CHECK(readEnabled(policyClient, &enabled) == MACCARE_POWERUI_INVALID_STATE);
        policyClient = fake(); policyClient.tornEnabledRead = YES;
        CHECK(readEnabled(policyClient, &enabled) == MACCARE_POWERUI_INVALID_STATE);
        policyClient = fake(); policyClient.readError = YES;
        CHECK(readEnabled(policyClient, &enabled) == MACCARE_POWERUI_CALL_FAILED);
        CHECK(policyClient.setterCalls == 0);
        // The public mutation entry points must reject this unprivileged test
        // before constructing any real PowerUI client or posting a notification.
        CHECK(geteuid() != 0);
        CHECK(maccare_powerui_clear_limit() == MACCARE_POWERUI_CALL_FAILED);
        CHECK(maccare_powerui_policy_preferences_changed() == MACCARE_POWERUI_CALL_FAILED);

        FakeNativeClient *client = fake();
        client.values = @[@100, @90, @80];
        int32_t limits[21]; size_t count = 0;
        CHECK(readLimits(client, limits, &count) == MACCARE_POWERUI_SUCCESS);
        CHECK(count == 3 && limits[0] == 80 && limits[1] == 90 && limits[2] == 100);

        NSArray *malformed = @[
            @[], @[@80], @[@80, @80, @100], @[@79, @100], @[@80, @101],
            @[@YES, @100], @[@80.5, @100], @[@(INFINITY), @100],
            @[@(NAN), @100], @[@"80", @100], @[[NSNull null], @100]
        ];
        for (NSArray *values in malformed) {
            client.values = values;
            CHECK(readLimits(client, limits, &count) == MACCARE_POWERUI_INVALID_STATE);
        }

        client = fake();
        MacCarePowerUIState state = {0};
        CHECK(readState(client, &state) == MACCARE_POWERUI_SUCCESS);
        CHECK(state.enabled == 0 && state.limit == 100);
        client = fake(); client.enabled = 1; client.limit = 85;
        CHECK(readState(client, &state) == MACCARE_POWERUI_SUCCESS);
        CHECK(state.enabled == 1 && state.limit == 85);
        client = fake(); client.enabled = 2;
        CHECK(readState(client, &state) == MACCARE_POWERUI_INVALID_STATE);
        client = fake(); client.limit = 79;
        CHECK(readState(client, &state) == MACCARE_POWERUI_INVALID_STATE);
        client = fake(); client.limit = 85; client.tornRead = YES;
        CHECK(readState(client, &state) == MACCARE_POWERUI_INVALID_STATE);
        client = fake(); client.readError = YES;
        CHECK(readState(client, &state) == MACCARE_POWERUI_CALL_FAILED);
        // A readable but unrepresentable snapshot is left for capture policy to
        // reject. It must not be silently normalized to another native state.
        client = fake(); client.limit = 85; client.enabled = 0;
        CHECK(readState(client, &state) == MACCARE_POWERUI_SUCCESS);
        CHECK(state.enabled == 0 && state.limit == 85);
        CHECK(client.setterCalls == 0);

        // These invalid arguments fail before even constructing a native client.
        CHECK(maccare_powerui_set_limit(79) == MACCARE_POWERUI_INVALID_LIMIT);
        CHECK(maccare_powerui_set_limit(101) == MACCARE_POWERUI_INVALID_LIMIT);
        CHECK(maccare_powerui_restore(0, 85) == MACCARE_POWERUI_INVALID_STATE);
        CHECK(maccare_powerui_restore(1, 100) == MACCARE_POWERUI_INVALID_STATE);
        CHECK(maccare_powerui_restore(2, 80) == MACCARE_POWERUI_INVALID_STATE);
        CHECK(maccare_powerui_read(NULL, limits, 21, &count) == MACCARE_POWERUI_INVALID_STATE);
        CHECK(maccare_powerui_read(&state, limits, 22, &count) == MACCARE_POWERUI_INVALID_STATE);
        puts("PowerUI boundary tests passed; zero native setters invoked.");
    }
    return 0;
}
