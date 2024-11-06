{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit clock;

interface

uses
   sysutils;

type
   TClock = class abstract
      function Now(): TDateTime; virtual; abstract;
   end;

   TSystemClock = class(TClock)
      function Now(): TDateTime; override;
   end;

   // A clock that returns the same value every time Now() is called.
   // The value is forgotten when Unlatch() is called. The value is taken from the given parent TClock when
   // the time is first read after the object is created or after Unlatch() is called.
   TStableClock = class(TClock)
   private
      FParentClock: TClock;
      FNow: TDateTime;
   public
      constructor Create(AParentClock: TClock);
      procedure Unlatch();
      function Now(): TDateTime; override;
   end;

implementation

uses math;

function TSystemClock.Now(): TDateTime;
begin
   Result := sysutils.Now();
end;

constructor TStableClock.Create(AParentClock: TClock);
begin
   inherited Create();
   FParentClock := AParentClock;
   FNow := NaN;
end;

procedure TStableClock.Unlatch();
begin
   FNow := NaN;
end;
            
function TStableClock.Now(): TDateTime;
begin
   if (IsNaN(FNow)) then
      FNow := FParentClock.Now();
   Result := FNow;
end;

end.
