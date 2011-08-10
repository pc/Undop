#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <ApplicationServices/ApplicationServices.h>

NSArray *_badSites;
NSDictionary *_browserScripts;

double lastCheckTime;
double checkDelta = 1.0;

#define fatal(fmt, ...) do { fprintf(stderr, fmt, ## __VA_ARGS__); exit(1); } while(0);

NSArray *badSites() {
  if(!_badSites) {
    _badSites = [[[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/.bad_sites", NSHomeDirectory()]]
                  componentsSeparatedByString:@"\n"] retain];
  }
  return _badSites;
}

NSDictionary *browserScripts() {
  NSString *safariScript = @"tell application \"Safari\"\n\treturn URL of front document as string\nend tell";
  NSString *chromeScript = @"tell application \"Google Chrome\"\n\treturn URL of active tab of window 1\nend tell";
  if(!_browserScripts) {
    _browserScripts = [[NSDictionary dictionaryWithObjects:
                                       [NSArray arrayWithObjects:
                                         [[NSAppleScript alloc] initWithSource:safariScript],
                                         [[NSAppleScript alloc] initWithSource:chromeScript], nil] 
                                     forKeys: [NSArray arrayWithObjects: @"Safari", @"Google Chrome", nil]] retain];
  }
  return _browserScripts;
}

NSString *currentHost(NSString *browser) {
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSString *host = nil;
  
  if((now - lastCheckTime) > checkDelta) {      
    NSDictionary *err;
    NSAppleScript *script = [browserScripts() objectForKey: browser];
    NSAppleEventDescriptor *ret = [script executeAndReturnError:&err];
    NSString *url = [ret stringValue];
    if(url) {
      host = [[[NSURL URLWithString:url] host] retain];
    }
    
    lastCheckTime = now;
  }
  
  return host;
}

void email(NSString *app, NSString *host) {
  int ret = system(
      [[NSString stringWithFormat:@"/usr/bin/ruby /Users/patrick/Projects/Undop/email.rb %@ %@",
                 app, host] UTF8String]
  );
  NSLog(@"ret: %d", ret);
}

int main(int argc, char **argv) 
{
  BOOL notified = NO;
  
  while(true) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new]; 

    NSString *activeApp = [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"];

    NSLog(@"activeApp: %@", activeApp);
    
    if([browserScripts() objectForKey: activeApp]) {
      NSString *host = currentHost(activeApp); 
      NSLog(@"host: %@", host);
      if(host) {
        if([badSites() containsObject: host]) {
          if(!notified) {
            notified = YES;
            email(activeApp, host);
          }
        }
        [host release];
      }
    } else if(notified) {
      notified = NO;
    }

    [pool release];

    sleep(1);
  }
}

