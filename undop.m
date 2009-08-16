#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <ApplicationServices/ApplicationServices.h>

NSArray *_badSites;

CFStringRef key = CFSTR(kIODisplayBrightnessKey);

double lastSafariTime;
double safariDelta = 1.0;
NSString *safariUrl = nil;
NSAppleScript *safariScript = nil;

float expectedBrightness;
float baselineBrightness;

#define fatal(fmt, ...) do { fprintf(stderr, fmt, ## __VA_ARGS__); exit(1); } while(0);

NSString *currentSafariURL() {
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  
  if((now - lastSafariTime) > safariDelta) {  
    if(!safariScript) {
      safariScript = [[NSAppleScript alloc] initWithSource:@"tell application \"Safari\"\n\treturn URL of front document as string\nend tell"];
    }
    
    NSDictionary *err;
    NSAppleEventDescriptor *ret = [safariScript executeAndReturnError:&err];
    NSString *url = [ret stringValue];
    [safariUrl release];
    
    if(url)
      safariUrl = [[[NSURL URLWithString:url] host] retain];
    else
      safariUrl = nil;
    
    lastSafariTime = now;
  }
  
  return safariUrl;
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

NSArray *badSites() {
  if(!_badSites) {
    _badSites = [[[NSString stringWithContentsOfFile:[NSString stringWithFormat:@"%@/.bad_sites", NSHomeDirectory()]]
                  componentsSeparatedByString:@"\n"] retain];
  }
  return _badSites;
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
    
    if([activeApp isEqualToString:@"Safari"] && [badSites() containsObject:currentSafariURL()]) {
      if(!shocked) {
        shocked = YES;
        decrementBrightness(service);
        brightness = getBrightness(service);
      }
    } else if(shocked) {
      shocked = NO;
    }
    
    if(brightness < baselineBrightness) {
      setBrightness(service, brightness + 0.01);
    }
    
    [pool release];
    
    sleep(1);
  }
}


