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
const
   Sign = $8000000000000000;
var
   QA, QB: QWord;
begin
   Assert(SizeOf(Double) = 8);
   Assert(SizeOf(QWord) = 8);
   if (IsNaN(A) or IsNaN(B)) then
   begin
      Result := False;
   end
   else
   if (QWord(A) = QWord(B)) then
   begin
      Result := True;
   end
   else
   if (IsInfinite(A) and IsInfinite(B)) then
   begin
      Assert(A <> B);
      Result := False;
   end
   else
   begin
      QA := QWord(A);
      QB := QWord(B);
      if ((QA and Sign) <> (QB and Sign)) then
      begin
         // if the sign is different, we don't consider the numbers sufficiently close to each other
         Result := False;
      end
      else
      if (QB > QA) then
      begin
         Result := (QB - QA) <= $7;
      end
      else
      begin
         Assert(QA > QB);
         Result := (QA - QB) <= $7;
      end;
   end;
end;

{$IFDEF TESTS}
{$PUSH}
{$IEEEERRORS OFF}
procedure TestEquals();
const
   A: Double = 1.00000000000000;
   B: Double = 1.00000000000000025;
   C: Double = 0.99999999999999975;
   D: Double = 0.5e-323;
   E: Double = -0.5e-323;
   F: Double = 1.00000000000000025e20;
   G: Double = 0.99999999999999975e20;
   H: Double = 1.00000000000000075e20;
   I: Double = 1.00000000000000100e20;
begin
   Assert(ApproximatelyEqual(0.0, 0.0));
   Assert(not ApproximatelyEqual(0.0, -0.0));
   Assert(not ApproximatelyEqual(0.0, 1.0));
   Assert(not ApproximatelyEqual(0.0000000001, 0.00000000001)); // 10x difference
   Assert(A <> B);
   Assert(A <> C);
   Assert(B <> C);
   Assert(D <> E);
   Assert(ApproximatelyEqual(A, B));
   Assert(ApproximatelyEqual(B, A));
   Assert(ApproximatelyEqual(A, C));
   Assert(ApproximatelyEqual(C, A));
   Assert(ApproximatelyEqual(B, C));
   Assert(ApproximatelyEqual(C, B));
   Assert(not ApproximatelyEqual(D, E));
   Assert(not ApproximatelyEqual(E, D));
   Assert(ApproximatelyEqual(D, 0.0));
   Assert(ApproximatelyEqual(E, -0.0));
   Assert(not ApproximatelyEqual(A, E));
   Assert(not ApproximatelyEqual(A-A, B-A));
   Assert(not ApproximatelyEqual(-A, B));
   Assert(ApproximatelyEqual(-A, -B));
   Assert(not ApproximatelyEqual(NaN, NaN));
   Assert(ApproximatelyEqual(Infinity, Infinity));
   Assert(ApproximatelyEqual(-Infinity, -Infinity));
   Assert(not ApproximatelyEqual(Infinity, -Infinity));
   Assert(ApproximatelyEqual(F, G));
   Assert(ApproximatelyEqual(F, H));
   Assert(ApproximatelyEqual(G, H));
   Assert(ApproximatelyEqual(F, I));
   Assert(ApproximatelyEqual(F, I));
   Assert(not ApproximatelyEqual(G, I));
end;
{$POP}
{$ENDIF}

initialization
   {$IFDEF TESTS}
      TestEquals();
   {$ENDIF}
end.
