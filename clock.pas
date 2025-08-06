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

   TMonotonicClock = class(TClock)
   private
      FParentClock: TClock;
      FLast: TDateTime;
   public
      constructor Create(AParentClock: TClock);
      function Now(): TDateTime; override;
   end;

   // A clock that returns the same value every time Now() is called.
   // The value is forgotten when Unlatch() is called. The value is taken from the given parent TClock when
   // the time is first read after the object is created or after Unlatch() is called.
   TStableClock = class(TClock)
   private
      FParentClock: TClock;
      FNow, FMax: TDateTime;
   public
      constructor Create(AParentClock: TClock);
      procedure Unlatch();
      procedure UnlatchUntil(Max: TDateTime);
      function Now(): TDateTime; override;
   end;

implementation

uses math;

function TSystemClock.Now(): TDateTime;
begin
   Result := sysutils.Now();
end;


constructor TMonotonicClock.Create(AParentClock: TClock);
begin
   inherited Create();
   FParentClock := AParentClock;
   FLast := FParentClock.Now;
end;
            
function TMonotonicClock.Now(): TDateTime;
begin
   Result := FParentClock.Now;
   if (Result < FLast) then
   begin
      {$IFOPT C+}
      Writeln('MONOTONIC CLOCK DETECTED NEGATIVE TIME (was: ', FLast, '; now: ', Result, ')');
      {$ENDIF}
      Result := FLast;
   end
   else
      FLast := Result;
end;


constructor TStableClock.Create(AParentClock: TClock);
begin
   inherited Create();
   FParentClock := AParentClock;
   FNow := NaN;
   FMax := NaN;
end;

procedure TStableClock.Unlatch();
begin
   FNow := NaN;
   FMax := NaN;
end;

procedure TStableClock.UnlatchUntil(Max: TDateTime);
begin
   FNow := NaN;
   FMax := Max;
end;
            
function TStableClock.Now(): TDateTime;
begin
   if (IsNaN(FNow)) then
   begin
      FNow := FParentClock.Now();
      if (not IsNaN(FMax) and (FNow > FMax)) then
         FNow := FMax;
   end;
   Result := FNow;
end;

end.
