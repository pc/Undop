#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <ApplicationServices/ApplicationServices.h>

NSArray *_badSites;
NSDictionary *_browserScripts;

CFStringRef key = CFSTR(kIODisplayBrightnessKey);

double lastCheckTime;
double checkDelta = 1.0;

float expectedBrightness;
float baselineBrightness;

#define fatal(fmt, ...) do { fprintf(stderr, fmt, ## __VA_ARGS__); exit(1); } while(0);

NSArray *badSites() {
  if(!_badSites) {
    _badSites = [[[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/.bad_sites", NSHomeDirectory()]]
                  componentsSeparatedByString:@"\n"] retain];
  }
  return _badSites;
}

NSDictionary *browserScripts() {
  if(!_browserScripts) {
    _browserScripts = [[NSDictionary 
		  dictionaryWithObjects: [NSArray arrayWithObjects: [[NSAppleScript alloc] initWithSource: @"tell application \"Safari\"\n\treturn URL of front document as string\nend tell"], [[NSAppleScript alloc] initWithSource:@"tell application \"Google Chrome\"\n\treturn URL of active tab of window 1\nend tell"], nil] 
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

float getBrightness(io_service_t service) {
  float brightness;
  CGDisplayErr err;
  
  err = IODisplayGetFloatParameter(service, kNilOptions, key, &brightness);
  
  if (err != kIOReturnSuccess)
    fatal("Couldn't get display brightness");
  
  if(fabs(expectedBrightness - brightness) > 0.01)
    baselineBrightness = brightness;
  
  expectedBrightness = brightness;  
  
  return brightness;
}

void setBrightness(io_service_t service, float brightness) {
  CGDisplayErr      err;

  err = IODisplaySetFloatParameter(service, kNilOptions, key, brightness);
  expectedBrightness = brightness;
  
  if (err != kIOReturnSuccess)
    fatal("Couldn't set display brightness");
}

void decrementBrightness(io_service_t service) {
  float brightness = getBrightness(service);    
  brightness -= 0.3;
  setBrightness(service, brightness);
}


int main(int argc, char **argv) 
{
  io_service_t      service;
  CGDirectDisplayID targetDisplay;
      
  targetDisplay = CGMainDisplayID();
  service = CGDisplayIOServicePort(targetDisplay);
  
  BOOL shocked = NO;
  
  while(true) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new]; 

    float brightness = getBrightness(service);
    
    NSString *activeApp = [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationName"];      
    
    if([browserScripts() objectForKey: activeApp]) {
      NSString *host = currentHost(activeApp); 
      if(host) {
        if([badSites() containsObject: host]) {
          if(!shocked) {
            shocked = YES;
            decrementBrightness(service);
            brightness = getBrightness(service);
          }
        }
        [host release];
      }
    }
    else if(shocked) {
      shocked = NO;
    }
    
    if(brightness < baselineBrightness) {
      setBrightness(service, brightness + 0.01);
    }
    
    [pool release];
    
    sleep(1);
  }
}

