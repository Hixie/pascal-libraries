{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit arrayutils;

interface

// Use as follows:
//
// FisherYatesShuffle(ArrayToShuffle[Low(ArrayToShuffle)], Length(ArrayToShuffle), SizeOf(ArrayToShuffle[0]));
procedure FisherYatesShuffle(var Buffer; const Count: Cardinal; const ElementSize: Cardinal);

function Join(const Input: array of RawByteString; const Separator: RawByteString): RawByteString;

type
   TSearchEvaluationFunc = function (const I: Integer): Integer is nested;

// binary searches between L and R and returns the lowest index for which SearchEvaluationFunc returns a positive value
function BinarySearch(L, R: Integer; const SearchEvaluationFunc: TSearchEvaluationFunc): Integer;

type
   TSwapFunc = procedure (const A, B: Integer) is nested;
   TCompareFunc = function (const A, B: Integer): Integer is nested;

// Use as follows:
//
// function Compare(const A, B: Cardinal): Integer;
// begin
//    Result := FArray[A] - FArray[B];
// end;
//
// procedure Swap(const A, B: Cardinal);
// var
//    Temp: T;
// begin
//    Temp := FArray[B];
//    FArray[A] := FArray[B];
//    FArray[B] := Temp;
// end;
//
// Sort(Length(FArray), Compare, Swap);
procedure Sort(const Length: Integer; const CompareFunc: TCompareFunc; const SwapFunc: TSwapFunc);

// Use as follows:
//
// specialize Sort<Double>(FArray);
generic procedure Sort<T>(var A: array of T);

// Use as follows:
//
// specialize QuickSort<Double>(FArray, 5, 10); // in-place sort the six items at positions 5..10
generic procedure QuickSort<T>(var A: array of T; L, R: Integer);

implementation

procedure FisherYatesShuffle(var Buffer; const Count: Cardinal; const ElementSize: Cardinal);
var
   Index, Subindex: Cardinal;
   Temp: Pointer;
begin
   if (Count < 2) then
      Exit;
   GetMem(Temp, ElementSize);
   for Index := Count-1 downto 1 do // $R-
   begin
      Subindex := Random(Index+1); // $R-
      {$POINTERMATH ON}
      Move((@Buffer+Subindex*ElementSize)^, Temp^, ElementSize);
      Move((@Buffer+Index*ElementSize)^, (@Buffer+Subindex*ElementSize)^, ElementSize);
      Move(Temp^, (@Buffer+Index*ElementSize)^, ElementSize);
      {$POINTERMATH OFF}
   end;
   FreeMem(Temp, ElementSize);
end;

function Join(const Input: array of RawByteString; const Separator: RawByteString): RawByteString;
var
   Index: Cardinal;
   Value: RawByteString;
begin
   Index := 0;
   for Value in Input do
      Inc(Index, Length(Value));
   SetLength(Result, Index + (Length(Input) - 1) * Length(Separator)); // {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   Index := 1;
   for Value in Input do
   begin
      if (Length(Value) > 0) then
      begin
         if ((Index > 1) and (Length(Separator) > 0)) then
         begin
            Move(Separator[1], Result[Index], Length(Separator));
            Inc(Index, Length(Separator));
         end;
         Move(Value[1], Result[Index], Length(Value));
         Inc(Index, Length(Value));
      end;  
   end;
end;

function BinarySearch(L, R: Integer; const SearchEvaluationFunc: TSearchEvaluationFunc): Integer;
var
   Comp: Integer;
begin
   while (L < R) do
   begin
      Result := L + ((R - L) shr 1); // $R-
      Comp := SearchEvaluationFunc(Result);
      if (Comp = 0) then
         exit;
      if (Comp < 0) then
      begin
         L := Result + 1; // $R-
      end
      else
      begin
         R := Result;
      end;
   end;
end;

procedure QuickSort(L, R: Integer; const CompareFunc: TCompareFunc; const SwapFunc: TSwapFunc);
var
   I, J, P: Integer;
begin
   // based on QuickSort in rtl/objpas/classes/lists.inc
   repeat
      I := L;
      J := R;
      P := (L + R) div 2; // $R-
      repeat
         while (CompareFunc(P, I) > 0) do
            Inc(I); // $R-
         while (CompareFunc(P, J) < 0) do
            Dec(J); // $R-
         if (I <= J) then
         begin
            SwapFunc(I, J);
            Inc(I); // $R-
            Dec(J); // $R-
         end;
      until I > J;
      if (L < J) then
         QuickSort(L, J, CompareFunc, SwapFunc);
      L := I;
   until I >= R;
end;

procedure Sort(const Length: Integer; const CompareFunc: TCompareFunc; const SwapFunc: TSwapFunc);
begin
   if (Length > 1) then
      QuickSort(0, Length-1, CompareFunc, SwapFunc); // $R-
end;

generic procedure QuickSort<T>(var A: array of T; L, R: Integer);
var
   I, J: Integer;
   P, Q: T;
begin
   // based on QuickSort in rtl/objpas/classes/lists.inc
   repeat
      I := L;
      J := R;
      P := A[(L + R) div 2];
      repeat
         while (P - A[I] > 0) do
            Inc(I); // $R-
         while (P - A[J] < 0) do
            Dec(J); // $R-
         if (I <= J) then
         begin
            Q := A[J];
            A[J] := A[I];
            A[I] := Q;
            Inc(I); // $R-
            Dec(J); // $R-
         end;
      until I > J;
      if (L < J) then
         specialize QuickSort<T>(A, L, J);
      L := I;
   until I >= R;
end;

generic procedure Sort<T>(var A: array of T);
begin
   if (Length(A) > 1) then
      specialize QuickSort<T>(A, Low(A), High(A)); // $R-
end;

end.
