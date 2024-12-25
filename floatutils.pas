{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit floatutils;

interface

{$DEFINE TESTS}

function ApproximatelyEqual(A, B: Double): Boolean;

implementation

{$IFDEF TESTS}
uses
   math;
{$ENDIF}

function ApproximatelyEqual(A, B: Double): Boolean;
begin
   Assert(SizeOf(Double) = 8);
   Assert(SizeOf(QWord) = 8);
   Result := (QWord(A) and not $7) = (QWord(B) and not $7);
end;

{$IFDEF TESTS}
{$PUSH}
{$IEEEERRORS OFF}
procedure TestEquals();
const
   A: Double = 1.00000000000000;
   B: Double = 1.000000000000001;
begin
   Assert(ApproximatelyEqual(0.0, 0.0));
   Assert(not ApproximatelyEqual(0.0, 1.0));
   Assert(not ApproximatelyEqual(0.0000000001, 0.00000000001)); // 10x difference
   Assert(A <> B);
   Assert(ApproximatelyEqual(A, B));
   Assert(not ApproximatelyEqual(A-A, B-A));
   Assert(not ApproximatelyEqual(-A, B));
   Assert(ApproximatelyEqual(-A, -B));
   Assert(ApproximatelyEqual(NaN, NaN));
   Assert(ApproximatelyEqual(Infinity, Infinity));
   Assert(not ApproximatelyEqual(Infinity, -Infinity));
end;
{$POP}
{$ENDIF}

initialization
   {$IFDEF TESTS}
      TestEquals();
   {$ENDIF}
end.