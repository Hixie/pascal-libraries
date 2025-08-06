{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit hashsettight;

// Compared to THashSet (in hashset.pas), this uses a lot less memory.
// It may also be quicker if you're mostly adding, enumerating, then
// resetting. If you remove nodes a lot, consider using THashSet, or
// develop a version of this that's based on robinhood hashing.

interface

type
   // for 8 bit numbers, use a regular pascal set.
   
   TTightHashUtils16 = record // for storing numbers 1..2^16-2 (not zero)
      class function Equals(const A, B: Word): Boolean; static; inline;
      class function Hash(const A: Word): DWord; static; inline;
      class function IsNotEmpty(const A: Word): Boolean; static; inline;
      class function IsOccupied(const A: Word): Boolean; static; inline;
      class function IsDeleted(const A: Word): Boolean; static; inline;
      class procedure Clear(var Buffer; Count: Cardinal); static; inline;
      class procedure Delete(var Buffer; Count: Cardinal); static; inline;
   end;
   
   TTightHashUtils32 = record // for storing numbers 1..2^32-2 (not zero)
      class function Equals(const A, B: DWord): Boolean; static; inline;
      class function Hash(const A: DWord): DWord; static; inline;
      class function IsNotEmpty(const A: DWord): Boolean; static; inline;
      class function IsOccupied(const A: DWord): Boolean; static; inline;
      class function IsDeleted(const A: DWord): Boolean; static; inline;
      class procedure Clear(var Buffer; Count: Cardinal); static; inline;
      class procedure Delete(var Buffer; Count: Cardinal); static; inline;
   end;
   
   TTightHashUtils64 = record // for storing numbers 1..2^64-2 (not zero)
      class function Equals(const A, B: QWord): Boolean; static; inline;
      class function Hash(const A: QWord): DWord; static; inline;
      class function IsNotEmpty(const A: QWord): Boolean; static; inline;
      class function IsOccupied(const A: QWord): Boolean; static; inline;
      class function IsDeleted(const A: QWord): Boolean; static; inline;
      class procedure Clear(var Buffer; Count: Cardinal); static; inline;
      class procedure Delete(var Buffer; Count: Cardinal); static; inline;
   end;
   
   TTightHashUtilsPtr = record // for storing pointers (not nil or Pointer(1))
      class function Equals(const A, B: Pointer): Boolean; static; inline;
      class function Hash(const A: Pointer): DWord; static; inline;
      class function IsNotEmpty(const A: Pointer): Boolean; static; inline;
      class function IsOccupied(const A: Pointer): Boolean; static; inline;
      class function IsDeleted(const A: Pointer): Boolean; static; inline;
      class procedure Clear(var Buffer; Count: Cardinal); static; inline;
      class procedure Delete(var Buffer; Count: Cardinal); static; inline;
   end;

   generic TTightHashSet <T, Utils> = class
    public
     type
      TSizeInt = DWord; // must match hash function output
      TSizeIntIndex = Int64; // must include TSizeInt
    strict protected
     type
      PArray = ^TArray;
      TArray = array[TSizeInt] of T;
     const
      kMaxLoad = 0.7; // Wikipedia: "With a good hash function, the average lookup cost is nearly constant as the load factor increases from 0 up to 0.7 or so"
     var
      FTable: PArray;
      FAllocated, FCount: TSizeInt;
      procedure DoubleSize();
      procedure Resize(const NewSize: TSizeInt);
      procedure InternalAdd(var Table: PArray; const Allocated: TSizeInt; const Value: T);
      procedure RemoveAt(const Hash: TSizeInt);
    strict private
      function GetIsEmpty(): Boolean; inline;
      function GetIsNotEmpty(): Boolean; inline;
    public
      constructor Create(const PredictedCount: TSizeInt = 0);
      destructor Destroy(); override;
      procedure Reset();
      procedure Add(const Value: T);
        // Add() should only be called for values that are not in the
        // table (as checked by Has()).
      function Intern(const Value: T): T;
        // Intern() first checks if the value is already in the table,
        // and if it is, it returns that previous value; otherwise, it
        // adds it to the table. The returned value can be useful for
        // types where Utils.Equals() can return true even for values
        // that are not pointer-equal, e.g. strings.
      procedure Remove(const Value: T);
        // Remove() should only be called for values that are in the
        // table (as checked by Has()).
      function Has(const Value: T): Boolean;
      property Count: TSizeInt read FCount;
      property IsEmpty: Boolean read GetIsEmpty;
      property IsNotEmpty: Boolean read GetIsNotEmpty;
    public
     type
       TEnumerator = class
        strict private
          FOwner: TTightHashSet;
          FIndex: TSizeIntIndex;
          function GetCurrent(): T;
        public
          constructor Create(const Owner: TTightHashSet);
          function MoveNext(): Boolean;
          property Current: T read GetCurrent;
          function GetEnumerator(): TEnumerator;
       end;
      function GetEnumerator(): TEnumerator;
   end;

   generic TObjectSet<T: class> = class (specialize TTightHashSet<T, TTightHashUtilsPtr>) end;
   generic TInterfaceSet<T> = class (specialize TTightHashSet<T, TTightHashUtilsPtr>) end;

implementation

// a lot of this is just copied from hashset.pas/hashtable.pas

uses
   sysutils, hashfunctions;

class function TTightHashUtils16.Equals(const A, B: Word): Boolean;
begin
   Result := A = B;
end;

class function TTightHashUtils16.Hash(const A: Word): DWord;
begin
   Result := Integer16Hash32(A);
end;

class function TTightHashUtils16.IsNotEmpty(const A: Word): Boolean;
begin
   Result := Word(A) <> 0;
end;

class function TTightHashUtils16.IsOccupied(const A: Word): Boolean;
begin
   Result := (Word(A) <> 0) and (Word(A) <> $FFFF);
end;

class function TTightHashUtils16.IsDeleted(const A: Word): Boolean;
begin
   Result := Word(A) = $FFFF;
end;

class procedure TTightHashUtils16.Clear(var Buffer; Count: Cardinal);
begin
   FillWord(Buffer, Count, 0);
end;

class procedure TTightHashUtils16.Delete(var Buffer; Count: Cardinal);
begin
   FillWord(Buffer, Count, $FFFF);
end;


class function TTightHashUtils32.Equals(const A, B: DWord): Boolean;
begin
   Result := A = B;
end;

class function TTightHashUtils32.Hash(const A: DWord): DWord;
begin
   Result := Integer32Hash32(A);
end;

class function TTightHashUtils32.IsNotEmpty(const A: DWord): Boolean;
begin
   Result := DWord(A) <> 0;
end;

class function TTightHashUtils32.IsOccupied(const A: DWord): Boolean;
begin
   Result := (DWord(A) <> 0) and (DWord(A) <> $FFFFFFFF);
end;

class function TTightHashUtils32.IsDeleted(const A: DWord): Boolean;
begin
   Result := DWord(A) = $FFFFFFFF;
end;

class procedure TTightHashUtils32.Clear(var Buffer; Count: Cardinal);
begin
   FillDWord(Buffer, Count, 0);
end;

class procedure TTightHashUtils32.Delete(var Buffer; Count: Cardinal);
begin
   FillDWord(Buffer, Count, $FFFFFFFF);
end;


class function TTightHashUtils64.Equals(const A, B: QWord): Boolean;
begin
   Result := A = B;
end;

class function TTightHashUtils64.Hash(const A: QWord): DWord;
begin
   Result := Integer64Hash32(A);
end;

class function TTightHashUtils64.IsNotEmpty(const A: QWord): Boolean;
begin
   Result := QWord(A) <> 0;
end;

class function TTightHashUtils64.IsOccupied(const A: QWord): Boolean;
begin
   Result := (QWord(A) <> 0) and (QWord(A) <> QWord($FFFFFFFFFFFFFFFF));
end;

class function TTightHashUtils64.IsDeleted(const A: QWord): Boolean;
begin
   Result := QWord(A) = QWord($FFFFFFFFFFFFFFFF);
end;

class procedure TTightHashUtils64.Clear(var Buffer; Count: Cardinal);
begin
   FillQWord(Buffer, Count, 0);
end;

class procedure TTightHashUtils64.Delete(var Buffer; Count: Cardinal);
begin
   FillQWord(Buffer, Count, QWord($FFFFFFFFFFFFFFFF));
end;


class function TTightHashUtilsPtr.Equals(const A, B: Pointer): Boolean;
begin
   Result := A = B;
end;

class function TTightHashUtilsPtr.Hash(const A: Pointer): DWord;
begin
   Result := PointerHash32(A);
end;

class function TTightHashUtilsPtr.IsNotEmpty(const A: Pointer): Boolean;
begin
   Result := PtrUInt(A) > 0;
end;

class function TTightHashUtilsPtr.IsOccupied(const A: Pointer): Boolean;
begin
   Result := PtrUInt(A) > 1;
end;

class function TTightHashUtilsPtr.IsDeleted(const A: Pointer): Boolean;
begin
   Result := PtrUInt(A) = 1;
end;

class procedure TTightHashUtilsPtr.Clear(var Buffer; Count: Cardinal);
begin
   {$IF SIZEOF(Pointer) = 4)}
     FillDWord(Buffer, Count, 0);
   {$ELSEIF SIZEOF(Pointer) = 8)}
     FillQWord(Buffer, Count, 0);
   {$ELSE}
     {$FATAL}
   {$ENDIF}
end;

class procedure TTightHashUtilsPtr.Delete(var Buffer; Count: Cardinal);
begin
   {$IF SIZEOF(Pointer) = 4)}
     FillDWord(Buffer, Count, 1);
   {$ELSEIF SIZEOF(Pointer) = 8)}
     FillQWord(Buffer, Count, 1);
   {$ELSE}
     {$FATAL}
   {$ENDIF}
end;


constructor TTightHashSet.Create(const PredictedCount: TSizeInt = 0);
const
   LoadFactorLimit = 1/kMaxLoad;
var
   AllocCount: TSizeInt;
begin
   inherited Create();
   if (PredictedCount > 0) then
   begin
      if (PredictedCount * LoadFactorLimit < High(TSizeInt)) then
         AllocCount := Trunc(PredictedCount * LoadFactorLimit) // $R-
      else
         AllocCount := High(TSizeInt);
      FTable := GetMem(AllocCount * SizeOf(T)); // $R-
      FAllocated := AllocCount;
      Utils.Clear(FTable^, AllocCount);
   end;
end;

destructor TTightHashSet.Destroy();
begin
   Reset();
   inherited;
end;

procedure TTightHashSet.Reset();
begin
   if (Assigned(FTable)) then
   begin
      FreeMem(FTable);
      FTable := nil;
      FAllocated := 0;
      FCount := 0;
   end;
end;

procedure TTightHashSet.DoubleSize();
begin
   Assert(FAllocated > 0);
   if (FAllocated * 2 < High(TSizeInt)) then
      Resize(FAllocated * 2) // $R-
   else
   if (FAllocated < High(TSizeInt)) then
      Resize(High(TSizeInt));
end;

procedure TTightHashSet.Resize(const NewSize: TSizeInt);
var
   NewSet: PArray;
   Index: TSizeInt;
   Item: T;
begin
   Assert(NewSize > 0);
   Assert(FAllocated > 0);
   if (NewSize <> FAllocated) then
   begin
      NewSet := GetMem(NewSize * SizeOf(T)); // $R-
      Utils.Clear(NewSet^, NewSize);
      for Index := 0 to FAllocated - 1 do // $R-
      begin
         Item := FTable^[Index];
         if (Utils.IsOccupied(Item)) then
            InternalAdd(NewSet, NewSize, Item);
      end;
      FreeMem(FTable);
      FTable := NewSet;
      FAllocated := NewSize;
   end;
end;

procedure TTightHashSet.InternalAdd(var Table: PArray; const Allocated: TSizeInt; const Value: T);
var
   Hash: TSizeInt;
begin
   Assert(Allocated > 0);
   Assert(Assigned(Table));
   Assert(Utils.IsOccupied(Value), 'tried to add nil value to tight hash set');
   Hash := Utils.Hash(Value) mod Allocated; // $R-
   while (Utils.IsOccupied(Table^[Hash])) do
   begin
      Inc(Hash);
      if (Hash = Allocated) then
         Hash := 0;
   end;
   Assert(not Utils.IsOccupied(Table^[Hash]));
   Table^[Hash] := Value;
end;

procedure TTightHashSet.Add(const Value: T);
begin
   Assert(not Has(Value), 'TTightHashSet.Add must not be called with a value that is already in the set.');
   Assert(Utils.IsOccupied(Value), 'tried to add nil value to tight hash set');
   Inc(FCount);
   if (FAllocated = 0) then
   begin
      Assert(not Assigned(FTable));
      Assert(FCount = 1);
      FAllocated := 2;
      FTable := GetMem(FAllocated * SizeOf(T)); // $R-
      Utils.Clear(FTable^, FAllocated);
   end
   else
   if (FCount / FAllocated > kMaxLoad) then
      DoubleSize();
   Assert(FCount < FAllocated);
   InternalAdd(FTable, FAllocated, Value);
end;

function TTightHashSet.Intern(const Value: T): T;
var
   Index, Hash: TSizeInt;
begin
   Assert(Utils.IsOccupied(Value), 'tried to intern nil value to tight hash set');
   if (FCount > 0) then
   begin
      Hash := Utils.Hash(Value) mod FAllocated; // $R-
      Index := Hash;
      while (Utils.IsNotEmpty(FTable^[Index])) do
      begin
         if (Utils.Equals(FTable^[Index], Value)) then
         begin
            Result := FTable^[Index];
            exit;
         end;
         Inc(Index);
         if (Index = FAllocated) then
            Index := 0;
         if (Index = Hash) then
         begin
            // Value is not in the set _and_ the set is full of sentinels.
            break;
         end;
      end;
   end;
   Add(Value);
   Result := Value;
end;

procedure TTightHashSet.RemoveAt(const Hash: TSizeInt);

   function Distance(A, B: TSizeInt): TSizeInt; inline;
   var
      Temp: TSizeIntIndex;
   begin
      Temp := A - B;
      if (Temp < 0) then
         Inc(Temp, FAllocated);
      Result := Temp; // $R-
   end;

   {$PUSH}
   {$GOTO ON} // forgive me father for i have sinned
   procedure Refill(Slot: TSizeInt);
   var
      Index, Ideal: TSizeInt;
   label
      top;
   begin
      Index := Slot;
      top:
      Inc(Index);
      if (Index = FAllocated) then
         Index := 0;
      while (Utils.IsNotEmpty(FTable^[Index])) do
      begin
         Ideal := Utils.Hash(FTable^[Index]) mod FAllocated; // $R-
         if (Distance(Index, Ideal) >= Distance(Index, Slot)) then
         begin
            FTable^[Slot] := FTable^[Index];
            Utils.Clear(FTable^[Index], 1);
            // What we want to do now is a tail recursion:
            //   Refill(Index);
            //   exit;
            // But the compiler doesn't do that so instead we hard-code it:
            Slot := Index;
            goto top;
            // It would be slightly safer if we could use "continue" with some outer loop
            // instead of a goto, but Pascal doesn't support that.
         end;
         Inc(Index);
         if (Index = FAllocated) then
            Index := 0;
         Assert(Index <> Hash); // surely we can't loop all the way around
      end;
   end;
   {$POP}

var
   Index: TSizeInt;
begin
   Utils.Delete(FTable^[Hash], 1);
   exit;
   // We could try to fix the table as follows:
   //   Utils.Clear(FTable^[Hash], 1);
   //   Refill(Hash);
   // But that's slow because of all the rehashing we have to
   // continually do. So instead we just leave a sentinel value.
   // However before doing that, let's just quickly check if the
   // previous values are also deleted; if they are, we can remove
   // the lot of them all at once to speed things up.
   Index := Hash;
   if (Index = 0) then
      Index := FAllocated;
   Dec(Index);
   while (Utils.IsDeleted(FTable^[Index])) do
   begin
      if (Index = 0) then
         Index := FAllocated - 1; // $R-
      Dec(Index);
   end;
   if (Utils.IsOccupied(FTable^[Index])) then
   begin
      Utils.Delete(FTable^[Hash], 1);
   end
   else
   begin
      Inc(Index);
      if (Index = FAllocated) then
         Index := 0;
      if (Index <= Hash) then
      begin
         Utils.Clear(FTable^[Index], Hash - Index + 1); // $R-
      end
      else
      begin
         Utils.Clear(FTable^[Index], FAllocated - Index); // $R-
         Utils.Clear(FTable^[0], Hash + 1); // $R-
      end;
   end;
end;

procedure TTightHashSet.Remove(const Value: T);
var
   Index, Hash: TSizeInt;
begin
   Assert(Utils.IsOccupied(Value), 'tried to remove nil value from tight hash set');
   Assert(Has(Value), 'cannot remove a value that is not in the set');
   if (FCount > 0) then
   begin
      Hash := Utils.Hash(Value) mod FAllocated; // $R-
      Index := Hash;
      while (Utils.IsNotEmpty(FTable^[Index])) do
      begin
         if (Utils.Equals(FTable^[Index], Value)) then
         begin
            Dec(FCount);
            if (FCount > 0) then
            begin
               RemoveAt(Index);
            end
            else
            begin
               Reset();
            end;
            exit;
         end;
         Inc(Index);
         if (Index = FAllocated) then
            Index := 0;
         Assert(Index <> Hash);
      end;
   end;
end;

function TTightHashSet.Has(const Value: T): Boolean;
var
   Index, Hash: TSizeIntIndex; // TODO: change this to TSizeInt when https://gitlab.com/freepascal.org/fpc/source/-/issues/41317 is fixed
   NewPosition: TSizeIntIndex;
begin
   Assert(Utils.IsOccupied(Value), 'tried to check for nil value in tight hash set');
   if (FCount > 0) then
   begin
      Hash := Utils.Hash(Value) mod FAllocated; // $R-
      Index := Hash;
      NewPosition := -1;
      while (Utils.IsNotEmpty(FTable^[Index])) do
      begin
         if (Utils.Equals(FTable^[Index], Value)) then
         begin
            if (NewPosition >= 0) then
            begin
               FTable^[NewPosition] := FTable^[Index];
               RemoveAt(Index); // $R- // TODO: remove when Index is a TSizeInt again
            end;
            Result := True;
            exit;
         end;
         if ((NewPosition < 0) and Utils.IsDeleted(FTable^[Index])) then
         begin
            NewPosition := Index;
         end;
         Inc(Index);
         if (Index = FAllocated) then
            Index := 0;
         if (Index = Hash) then
         begin
            // Value is not in the set _and_ the set is full of sentinels.
            // TODO: Consider repacking the entire set.
            break;
         end;
      end;
   end;
   Result := False;
end;

constructor TTightHashSet.TEnumerator.Create(const Owner: TTightHashSet);
begin
   Assert(Assigned(Owner));
   FOwner := Owner;
   FIndex := -1;
end;

function TTightHashSet.TEnumerator.GetCurrent(): T;
begin
   Result := FOwner.FTable^[FIndex];
end;

function TTightHashSet.TEnumerator.MoveNext(): Boolean;
begin
   Assert(Assigned(FOwner));
   if (FIndex < FOwner.FAllocated) then
   begin
      repeat
         Inc(FIndex);
         Result := FIndex < FOwner.FAllocated;
      until (not Result) or (Utils.IsOccupied(FOwner.FTable^[FIndex]));
   end
   else
      Result := False;
end;

function TTightHashSet.TEnumerator.GetEnumerator(): TEnumerator;
begin
   Result := Self;
end;

function TTightHashSet.GetEnumerator(): TEnumerator;
begin
   Result := TEnumerator.Create(Self);
end;

function TTightHashSet.GetIsEmpty(): Boolean;
begin
   Result := Count = 0;
end;

function TTightHashSet.GetIsNotEmpty(): Boolean;
begin
   Result := Count > 0;
end;

end.
