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

   TRootClock = class abstract (TClock)
      constructor Create(); virtual; abstract;
   end;
   TRootClockClass = class of TRootClock;
   
   TSystemClock = class(TRootClock)
      constructor Create(); override;
      function Now(): TDateTime; override;
   end;

   TComposedClock = class abstract (TClock)
   protected
      FParentClock: TClock;
   public
      constructor Create(AParentClock: TClock); virtual;
   end;
   
   TMonotonicClock = class(TComposedClock)
   private
      FLast: TDateTime;
   public
      constructor Create(AParentClock: TClock); override;
      function Now(): TDateTime; override;
   end;

   // A clock that returns the same value every time Now() is called.
   // The value is forgotten when Unlatch() is called. The value is taken from the given parent TClock when
   // the time is first read after the object is created or after Unlatch() is called.
   TStableClock = class(TComposedClock)
   private
      FNow, FMax: TDateTime;
   public
      constructor Create(AParentClock: TClock); override;
      procedure Unlatch();
      procedure UnlatchUntil(Max: TDateTime);
      function Now(): TDateTime; override;
   end;

implementation

uses math;

constructor TSystemClock.Create();
begin
end;

function TSystemClock.Now(): TDateTime;
begin
   Result := sysutils.Now();
end;


constructor TComposedClock.Create(AParentClock: TClock);
begin
   inherited Create();
   FParentClock := AParentClock;
end;


constructor TMonotonicClock.Create(AParentClock: TClock);
begin
   inherited Create(AParentClock);
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
   inherited Create(AParentClock);
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
   Assert(Assigned(FParentClock));
   if (IsNaN(FNow)) then
   begin
      FNow := FParentClock.Now();
      if (not IsNaN(FMax) and (FNow > FMax)) then
         FNow := FMax;
   end;
   Result := FNow;
end;

end.
