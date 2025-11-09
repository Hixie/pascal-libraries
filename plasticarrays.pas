{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit plasticarrays;

interface

const
   kGrowthFactor: Double = 1.25;

type
   generic PlasticArray <T, Utils> = record
    private
     type
      PPlasticArray = ^PlasticArray;
      TArray = array of T;
     var
      FArray: TArray;
      FFilledLength: Cardinal;
      function GetItem(const Index: Cardinal): T; inline;
      procedure SetItem(const Index: Cardinal; const Item: T); inline;
      function GetLast(): T; inline;
      procedure SetLast(const Item: T); inline;
      procedure SetFilledLength(const NewFilledLength: Cardinal); inline;
      function GetIsEmpty(): Boolean; inline;
      function GetIsNotEmpty(): Boolean; inline;
    public
      // these calls are all O(1) except as noted
      procedure Init(LikelyLength: Cardinal = 0); inline; // call this if the PlasticArray is not pre-zeroed
        // (i.e. using this as a class member is fine; but if you use this in a procedure, call Init() first)
        // this is because the FFilledLength member is not managed by the compiler
        // This call is up to O(LikelyLength), because it zeroes out the array.
      procedure Push(const Item: T); inline; // expensive if it requires the length to be increased
      function Pop(): T; inline; // trivial, does not free memory for slot that is popped
      procedure Empty(); inline; // trivial, does not free memory
      property Length: Cardinal read FFilledLength write SetFilledLength; // expensive if it requires the length to be increased
      property Items[Index: Cardinal]: T read GetItem write SetItem; default;
      property Last: T read GetLast write SetLast;
      property IsEmpty: Boolean read GetIsEmpty;
      property IsNotEmpty: Boolean read GetIsNotEmpty;
    public
      // The following calls are relatively expensive for various reasons
      procedure Squeeze(); inline; // reduces memory usage to minimum required
      procedure InsertAt(const Index: Cardinal; const Value: T); // does a memory move (if Index < FFilledLength)
      procedure RemoveAt(const Index: Cardinal); // does a memory move
      procedure Remove(const Value: T); // does a linear search (from end), then memory move
      procedure RemoveAll(const Value: T); // walks the entire array
      procedure Replace(const Value: T; const NewValue: T); // does a linear search (from end)
      function Contains(const Value: T): Boolean; // linear search
      function Contains(const Value: T; out IndexResult: Cardinal): Boolean; // linear search; IndexResult is only valid if result is True
      procedure RemoveShiftLeftInsert(const RemoveIndex, InsertIndex: Cardinal; NewValue: T);
      function Distill(): TArray; inline; // calls Squeeze(), extracts the array, then calls Init()
      function Copy(): TArray; inline; // copies the entire array to a new array
    public
     type
      TCompareFunc = function (const A, B: T): Integer is nested;
      procedure Sort(const CompareFunc: TCompareFunc);
      procedure Sort();
      procedure SortSubrange(L, R: Integer; const CompareFunc: TCompareFunc);
      procedure SortSubrange(L, R: Integer);
      procedure Shuffle();
      function Find(Target: T): Cardinal; // binary search; assumes sorted input and Utils with functioning comparators; only works for arrays with FFilledLength <= High(Integer)
    public
     type
       TEnumerator = class
        strict private
          FTarget: PPlasticArray;
          FIndex: Cardinal;
          function GetCurrent(): T;
        public
          constructor Create(const Target: PPlasticArray);
          function MoveNext(): Boolean;
          property Current: T read GetCurrent;
       end;
      function GetEnumerator(): TEnumerator; inline;
    public
     type
       TFilteredEnumerator = class
        strict private
          FTarget: PPlasticArray;
          FIndex: Cardinal;
          FFilter: T;
          function GetCurrent(): T;
        public
          constructor Create(const Target: PPlasticArray; const Filter: T);
          function MoveNext(): Boolean;
          property Current: T read GetCurrent;
          function GetEnumerator(): TFilteredEnumerator; inline;
       end;
      function Without(const Value: T): TFilteredEnumerator; inline;
    public
     type
      TReadOnlyView = class
       private
        var
          FArray: PPlasticArray;
         constructor Create(AArray: PPlasticArray);
         function GetFilledLength(): Cardinal; inline;
         function GetItem(Index: Cardinal): T; inline;
         function GetLast(): T; inline;
       public
         // these calls are all O(1)
         property Length: Cardinal read GetFilledLength;
         property Items[Index: Cardinal]: T read GetItem; default;
         property Last: T read GetLast;
         function GetEnumerator(): TEnumerator; inline;
      end;
      function GetReadOnlyView(): TReadOnlyView;
   end;

implementation

uses
   arrayutils;

procedure PlasticArray.Init(LikelyLength: Cardinal = 0);
begin
   FFilledLength := 0;
   SetLength(FArray, LikelyLength);
end;

function PlasticArray.GetItem(const Index: Cardinal): T;
begin
   Assert(Index < FFilledLength);
   Result := FArray[Index];
end;

procedure PlasticArray.SetItem(const Index: Cardinal; const Item: T);
begin
   Assert(Index < FFilledLength);
   FArray[Index] := Item;
end;

function PlasticArray.GetLast(): T;
begin
   Assert(FFilledLength > 0);
   Result := FArray[FFilledLength-1]; // $R-
end;

procedure PlasticArray.SetLast(const Item: T);
begin
   Assert(FFilledLength > 0);
   FArray[FFilledLength-1] := Item;
end;

function PlasticArray.GetIsEmpty(): Boolean;
begin
   Result := FFilledLength = 0;
end;

function PlasticArray.GetIsNotEmpty(): Boolean;
begin
   Result := FFilledLength > 0;
end;

procedure PlasticArray.SetFilledLength(const NewFilledLength: Cardinal);
var
   NewLength: Int64;
begin
   Assert(NewFilledLength <= High(Integer));
   FFilledLength := NewFilledLength;
   if (FFilledLength > System.Length(FArray)) then
   begin
      NewLength := Trunc(FFilledLength * kGrowthFactor) + 1;
      if (NewLength > High(Integer)) then
         NewLength := High(Integer);
      if (NewLength < NewFilledLength) then
         NewLength := NewFilledLength;
      SetLength(FArray, NewLength);
   end;
end;

procedure PlasticArray.Squeeze();
begin
   if (System.Length(FArray) <> FFilledLength) then
      SetLength(FArray, FFilledLength);
end;

procedure PlasticArray.Empty();
begin
   FFilledLength := 0;
end;

procedure PlasticArray.Push(const Item: T);
begin
   Assert(FFilledLength < High(Cardinal));
   SetFilledLength(FFilledLength + 1); // $R-
   FArray[FFilledLength-1] := Item;
end;

function PlasticArray.Pop(): T;
begin
   Assert(FFilledLength > 0);
   Dec(FFilledLength);
   Result := FArray[FFilledLength];
end;

procedure PlasticArray.InsertAt(const Index: Cardinal; const Value: T);
begin
   if (Index = FFilledLength) then
   begin
      Push(Value);
      exit;
   end;
   Assert(FFilledLength < High(Cardinal));
   SetFilledLength(FFilledLength + 1); // $R-
   Move(FArray[Index], FArray[Index+1], (FFilledLength-Index-1)*SizeOf(T));
   FArray[Index] := Value;
end;

procedure PlasticArray.RemoveAt(const Index: Cardinal);
begin
   Assert(FFilledLength > 0);
   Assert(Index < FFilledLength);
   Dec(FFilledLength);
   if (Index < FFilledLength) then
      Move(FArray[Index+1], FArray[Index], (FFilledLength-Index)*SizeOf(T));
end;

procedure PlasticArray.Remove(const Value: T);
var
   Index: Cardinal;
begin
   if (FFilledLength > 0) then
   begin
      Index := FFilledLength;
      repeat
         Dec(Index);
         if (Utils.Equals(FArray[Index], Value)) then
         begin
            RemoveAt(Index);
            exit;
         end;
      until Index = Low(FArray);
   end;
end;

procedure PlasticArray.RemoveAll(const Value: T);
var
   ReadIndex, WriteIndex: Cardinal;
begin
   ReadIndex := Low(FArray);
   WriteIndex := Low(FArray);
   while (ReadIndex < FFilledLength) do
   begin
      if (not Utils.Equals(FArray[ReadIndex], Value)) then
      begin
         if (WriteIndex <> ReadIndex) then
            FArray[WriteIndex] := FArray[ReadIndex];
         Inc(WriteIndex);
      end;
      Inc(ReadIndex);
   end;
   FFilledLength := WriteIndex;
end;

procedure PlasticArray.Replace(const Value: T; const NewValue: T);
var
   Index: Cardinal;
begin
   if (FFilledLength > 0) then
   begin
      Index := FFilledLength;
      repeat
         Dec(Index);
         if (Utils.Equals(FArray[Index], Value)) then
         begin
            FArray[Index] := NewValue;
            exit;
         end;
      until Index = Low(FArray);
   end;
end;

function PlasticArray.Contains(const Value: T): Boolean;
var
   Index: Cardinal;
begin
   if (FFilledLength > 0) then
      for Index := FFilledLength-1 downto Low(FArray) do // $R-
         if (Utils.Equals(FArray[Index], Value)) then
         begin
            Result := True;
            exit;
         end;
   Result := False;
end;

function PlasticArray.Contains(const Value: T; out IndexResult: Cardinal): Boolean;
var
   Index: Cardinal;
begin
   if (FFilledLength > 0) then
      for Index := FFilledLength-1 downto Low(FArray) do // $R-
         if (Utils.Equals(FArray[Index], Value)) then
         begin
            Result := True;
            IndexResult := Index;
            exit;
         end;
   Result := False;
   {$IFOPT C+} IndexResult := High(IndexResult); {$ENDIF}
end;

procedure PlasticArray.RemoveShiftLeftInsert(const RemoveIndex, InsertIndex: Cardinal; NewValue: T);
begin
   Assert(RemoveIndex <= InsertIndex);
   Assert(InsertIndex < FFilledLength);
   Assert(System.Length(FArray) >= FFilledLength);
   if (InsertIndex = RemoveIndex) then
   begin
      FArray[InsertIndex] := NewValue;
   end
   else
   begin
      Move(FArray[RemoveIndex+1], FArray[RemoveIndex], (InsertIndex-RemoveIndex)*SizeOf(T));
      FArray[InsertIndex] := NewValue;
   end;
end;

function PlasticArray.Distill(): TArray;
begin
   Squeeze();
   Result := FArray;
   Init();
   Assert((not Assigned(Result)) or (Pointer(Result) <> Pointer(FArray)));
end;

function PlasticArray.Copy(): TArray;
begin
   Result := system.Copy(FArray, 0, FFilledLength);
end;

procedure PlasticArray.SortSubrange(L, R: Integer; const CompareFunc: TCompareFunc);
var
   I, J : Integer;
   P, Q : T;
begin
   Assert(L < R);
   // based on QuickSort in rtl/objpas/classes/lists.inc
   repeat
      I := L;
      J := R;
      P := FArray[(L + R) div 2];
      repeat
         while (CompareFunc(P, FArray[I]) > 0) do
            I := I + 1; // $R-
         while (CompareFunc(P, FArray[J]) < 0) do
            J := J - 1; // $R-
         if (I <= J) then
         begin
            Q := FArray[I];
            FArray[I] := FArray[J];
            FArray[J] := Q;
            I := I + 1; // $R-
            J := J - 1; // $R-
         end;
      until I > J;
      if (L < J) then
         SortSubrange(L, J, CompareFunc);
      L := I;
   until I >= R;
end;

procedure PlasticArray.Sort(const CompareFunc: TCompareFunc);
begin
   Assert(FFilledLength < High(Integer));
   if (FFilledLength > 1) then
      SortSubrange(Low(FArray), FFilledLength-1, CompareFunc); // $R-
end;

procedure PlasticArray.SortSubrange(L, R: Integer);
var
   I, J : Integer;
   P, Q : T;
begin
   Assert(L < R);
   // based on QuickSort in rtl/objpas/classes/lists.inc
   repeat
      I := L;
      J := R;
      P := FArray[(L + R) div 2];
      repeat
         while (Utils.GreaterThan(P, FArray[I])) do
            I := I + 1; // $R-
         while (Utils.LessThan(P, FArray[J])) do
            J := J - 1; // $R-
         if (I <= J) then
         begin
            Q := FArray[I];
            FArray[I] := FArray[J];
            FArray[J] := Q;
            I := I + 1; // $R-
            J := J - 1; // $R-
         end;
      until I > J;
      if (L < J) then
         SortSubrange(L, J);
      L := I;
   until I >= R;
end;

procedure PlasticArray.Sort();
begin
   Assert(FFilledLength < High(Integer));
   if (FFilledLength > 1) then
      SortSubrange(Low(FArray), FFilledLength-1); // $R-
end;

procedure PlasticArray.Shuffle();
begin
   if (FFilledLength > 1) then
      FisherYatesShuffle(FArray[0], FFilledLength, SizeOf(T)); // $R-
end;

function PlasticArray.Find(Target: T): Cardinal;

   function Search(const I: Integer): Int64;
   begin
      Result := Utils.Compare(FArray[I], Target);
   end;
   
begin
   if (FFilledLength = 0) then
   begin
      Result := 0;
      exit;
   end;
   Result := BinarySearch(0, FFilledLength, @Search); // $R-
end;


constructor PlasticArray.TEnumerator.Create(const Target: PPlasticArray);
begin
   inherited Create();
   Assert(Assigned(Target));
   FTarget := Target;
end;

function PlasticArray.TEnumerator.GetCurrent(): T;
begin
   Assert(FIndex > 0);
   Result := FTarget^[FIndex-1]; // $R-
end;

function PlasticArray.TEnumerator.MoveNext(): Boolean;
begin
   Result := FIndex < FTarget^.Length;
   Inc(FIndex);
end;

function PlasticArray.GetEnumerator(): TEnumerator;
begin
   Result := TEnumerator.Create(@Self);
end;


constructor PlasticArray.TFilteredEnumerator.Create(const Target: PPlasticArray; const Filter: T);
begin
   inherited Create();
   Assert(Assigned(Target));
   FTarget := Target;
   FFilter := Filter;
end;

function PlasticArray.TFilteredEnumerator.GetCurrent(): T;
begin
   Assert(FIndex > 0);
   Result := FTarget^[FIndex-1]; // $R-
end;

function PlasticArray.TFilteredEnumerator.MoveNext(): Boolean;
begin
   repeat
      Inc(FIndex);
   until (FIndex > FTarget^.Length) or (not Utils.Equals(FTarget^[FIndex - 1], FFilter)); // $R-
   Result := FIndex <= FTarget^.Length;
end;

function PlasticArray.TFilteredEnumerator.GetEnumerator(): TFilteredEnumerator;
begin
   Result := Self;
end;

function PlasticArray.Without(const Value: T): TFilteredEnumerator;
begin
   Result := TFilteredEnumerator.Create(@Self, Value);
end;


constructor PlasticArray.TReadOnlyView.Create(AArray: PPlasticArray);
begin
   Assert(Assigned(AArray));
   FArray := AArray;
end;

function PlasticArray.TReadOnlyView.GetFilledLength(): Cardinal;
begin
   Result := FArray^.Length;
end;

function PlasticArray.TReadOnlyView.GetItem(Index: Cardinal): T;
begin
   Result := FArray^[Index];
end;

function PlasticArray.TReadOnlyView.GetLast(): T;
begin
   Result := FArray^.GetLast();
end;

function PlasticArray.TReadOnlyView.GetEnumerator(): TEnumerator;
begin
   Result := FArray^.GetEnumerator();
end;

function PlasticArray.GetReadOnlyView(): PlasticArray.TReadOnlyView;
begin
   Result := TReadOnlyView.Create(@Self);
end;

end.
