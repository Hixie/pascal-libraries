{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit hashtable;

// warning: if you edit the implementation section of this unit but
// not its interface, dependent units won't be recompiled, so force it
// with -B

interface

uses
   hashfunctions;

(* How to use THashTable ******************************************************************
 * This generates a TFoo to TBar hash table with name TFooHashTable.
 * Replace FooHash32 with one of the functions in hashfunctions.pas, based on TFoo's type
 * If TFoo is a type that doesn't have built-in =/</> operators, you'll need to define
 * your own utility record type instead of using DefaultUtils; see genericutils.pas

   type
      TFooUtils = specialize DefaultUtils <TFoo>;
      TFooHashTable = class(specialize THashTable <TFoo, TBar, TFooUtils>)
       public
        constructor Create(PredictedCount: THashTableSizeInt = 8);
      end;

   constructor TFooHashTable.Create(PredictedCount: THashTableSizeInt = 8);
   begin
      inherited Create(@FooHash32, PredictedCount);
   end;

 * If you just have a one-off instance, you can skip defining a convenience constructor
 * and just do it like this instead:

   type
      TFooUtils = specialize DefaultUtils <TFoo>;
      TFooHashTable = specialize THashTable <TFoo, TBar, TFooUtils>;

   var
      Hash: TFooHashTable;

   Hash := TFooHashTable.Create(@FooHash32, PredictedCount);

 * If the TValue type is mutable (i.e. not a value like a pointer or integer,
 * but e.g. a record that exposes an interface that mutates its fields like
 * PlasticArray), values should be obtained using ItemsPointer rather than
 * Items (or the default [] operator). This will return a pointer to the value
 * held in the hashtable. This pointer will remain valid for as long as it is
 * in the hashtable; if it is removed, or if the hashtable is emptied or
 * disposed, then the pointer will no longer be valid.
 *
 * Be careful not to make copies of such data (e.g. by dereferencing the
 * pointer in a way that makes a temporary), as changes to copies will not
 * propagate. Similarly, avoid using the values iterator, as it returns
 * copies.
 *
 * Keys should never by mutable types.
 *
 * ****************************************************************************************)

{ The best case memory usage of a hash table on a 64 bit system is:

    40 + 16 + 1.4 * Count * 8 + Count * (SizeOf(TKey) + SizeOf(TValue) + 8)

  The 40 bytes is the InstanceSize of a THashTable.

  The 16 bytes is the overhead of the dynamic array used for the table.

  The 1.4 is the overhead of a fully-loaded hash table (with max load
  factor 0.7).

  The Count is the number of entries in the table.

  The first 8 is the pointer size; there are 1.4 * Count pointers in
  the hash table (those are the entries in the table).

  The second 8 is the linked list pointer; there are Count linked list
  entries, each of which has a key and a value in addition to the
  linked list pointer. The expression above says "SizeOf(TKey)" and
  "SizeOf(TValue)" but if these are less than 8 bytes then alignment
  probably forces them to 8 bytes anyway.

  So for a hash table with 14 items with keys and values each of 8
  bytes, the hash table will take about 549 bytes. For 64 items, it
  would take about 2.2KB.

  (For contrast, a static array of 64 items of 8 bytes takes 512
  bytes, and if stored on the stack, doesn't even need the 8 byte
  pointer to the object!)

}

type
   generic THashTable <TKey, TValue, Utils> = class
    public
     type
      PValue = ^TValue;
    strict protected
     type
      PPHashTableEntry = ^PHashTableEntry;
      PHashTableEntry = ^THashTableEntry;
      THashTableEntry = record
        Key: TKey;
        Value: TValue;
        Next: PHashTableEntry;
      end;
      THashFunction = function (const Key: TKey): DWord;
     const
      kMaxLoadFactor = 0.7; // Wikipedia: "With a good hash function, the average lookup cost is nearly constant as the load factor increases from 0 up to 0.7 or so";
     var
      FTable: array of PHashTableEntry;
      FCount: THashTableSizeInt;
      FHashFunction: THashFunction;
      procedure DoubleSize();
      procedure Resize(const NewSize: THashTableSizeInt);
      procedure PrepareForSize(PredictedCount: THashTableSizeInt);
      function InternalAdd(const Key: TKey): PHashTableEntry;
      procedure Update(const Key: TKey; const Value: TValue); // will call Add() if the key isn't already present
      function Get(const Key: TKey): TValue;
      function GetPtr(const Key: TKey): PValue;
      function GetKeyForEntry(const Entry: Pointer): TKey;
      function GetValueForEntry(const Entry: Pointer): TValue;
      function GetValuePtrForEntry(const Entry: Pointer): PValue;
      procedure AdvanceEnumerator(var Current: Pointer; var Index: THashTableSizeInt);
      procedure RemoveEntry(Current: Pointer; Index: THashTableSizeInt);
    strict private
      function GetIsEmpty(): Boolean; inline;
      function GetIsNotEmpty(): Boolean; inline;
    public
      constructor Create(const AHashFunction: THashFunction; const PredictedCount: THashTableSizeInt = 8);
      destructor Destroy(); override;
      procedure Empty();
      procedure Remove(const Key: TKey);
      function Has(const Key: TKey): Boolean;
      function AddDefault(const Key: TKey): PValue; inline; // adds the value as Default(TValue) (could have been called AddPtr)
      procedure Add(const Key: TKey; const Value: TValue); inline;
      function Clone(): THashTable;
      function GetOrAddPtr(const Key: TKey): PValue; // only useful with fully managed types, or if result is always entirely overwritten (otherwise there's no way to distinguish newly added values from existing values)
      property Items[Key: TKey]: TValue read Get write Update; default;
      property ItemsPtr[Key: TKey]: PValue read GetPtr;
      {$IFDEF DEBUG} procedure Histogram(var F: Text); {$ENDIF}
      property Count: THashTableSizeInt read FCount;
      property IsEmpty: Boolean read GetIsEmpty;
      property IsNotEmpty: Boolean read GetIsNotEmpty;
    public
     type
       TKeyEnumerator = class
        strict private
          FOwner: THashTable;
          FIndex: THashTableSizeInt;
          FCurrent: Pointer;
          function GetCurrent(): TKey;
          function GetCurrentValue(): TValue;
        public
          constructor Create(const Owner: THashTable);
          function MoveNext(): Boolean;
          property Current: TKey read GetCurrent;
          property CurrentValue: TValue read GetCurrentValue;
          function GetEnumerator(): TKeyEnumerator;
          property HashTable: THashTable read FOwner;
       end;
      function GetEnumerator(): TKeyEnumerator;
    public
     type
       TValueEnumerator = class
        strict private
          FOwner: THashTable;
          FIndex: THashTableSizeInt;
          FCurrent: Pointer;
          function GetCurrent(): TValue;
        public
          constructor Create(const Owner: THashTable);
          function MoveNext(): Boolean;
          property Current: TValue read GetCurrent;
          function GetEnumerator(): TValueEnumerator;
          property HashTable: THashTable read FOwner;
       end;
      function Values(): TValueEnumerator;
    public
     type
       TValuePtrEnumerator = class
        strict private
          FOwner: THashTable;
          FIndex: THashTableSizeInt;
          FCurrent: Pointer;
          FAlreadyAdvanced: Boolean;
          function GetCurrent(): PValue;
          function GetCurrentKey(): TKey; inline;
        public
          constructor Create(const Owner: THashTable);
          function MoveNext(): Boolean;
          procedure RemoveCurrent();
          property Current: PValue read GetCurrent;
          property CurrentKey: TKey read GetCurrentKey;
          function GetEnumerator(): TValuePtrEnumerator;
          property HashTable: THashTable read FOwner;
       end;
      function ValuePtrs(): TValuePtrEnumerator;
   end;

   // XXX would be good to see if we can cache the enumerators mentioned above
   // e.g. by tracking if it's still in use, and having a "master" enumerator (cached the first time it's created) which
   // we only free when it's done, and whose .Free doesn't do anything if the instance is a master, or something

implementation

uses
   sysutils;

constructor THashTable.Create(const AHashFunction: THashFunction; const PredictedCount: THashTableSizeInt = 8);
begin
   inherited Create();
   Assert(Assigned(AHashFunction));
   FHashFunction := AHashFunction;
   Assert(PredictedCount > 0);
   PrepareForSize(PredictedCount);
end;

destructor THashTable.Destroy();
begin
   Empty();
   inherited;
end;

procedure THashTable.Empty();
var
   Index: THashTableSizeInt;
   Item, LastItem: PHashTableEntry;
begin
   if (Length(FTable) > 0) then
      for Index := Low(FTable) to High(FTable) do
      begin
         Item := FTable[Index];
         while (Assigned(Item)) do
         begin
            LastItem := Item;
            Item := Item^.Next;
            Dispose(LastItem);
         end;
         FTable[Index] := nil;
      end;
   FCount := 0;
end;

procedure THashTable.DoubleSize();
begin
   Assert(Length(FTable) > 0);
   if (Length(FTable)*2 < High(THashTableSizeInt)) then
      Resize(Length(FTable) * 2) // $R-
   else
   if (Length(FTable) < High(THashTableSizeInt)) then
      Resize(High(THashTableSizeInt));
end;

procedure THashTable.PrepareForSize(PredictedCount: THashTableSizeInt);
const
   LoadFactorLimit = 1/kMaxLoadFactor;
begin
   Assert(PredictedCount > 0);
   if (PredictedCount * LoadFactorLimit < High(THashTableSizeInt)) then
      PredictedCount := Trunc(PredictedCount * LoadFactorLimit) // $R-
   else
      PredictedCount := High(THashTableSizeInt);
   if (FCount > 0) then
      Resize(PredictedCount)
   else
      SetLength(FTable, PredictedCount);
end;

procedure THashTable.Resize(const NewSize: THashTableSizeInt);
var
   NewTable: array of PHashTableEntry;
   Index: THashTableSizeInt;
   Item, NextItem: PHashTableEntry;
   Hash: DWord;
begin
   Assert(NewSize > 0);
   if (NewSize <> Length(FTable)) then
   begin
      SetLength(NewTable, NewSize);
      Assert(Length(FTable) > 0);
      for Index := Low(FTable) to High(FTable) do // $R-
      begin
         Item := FTable[Index];
         while (Assigned(Item)) do
         begin
            NextItem := Item^.Next;
            { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
            Hash := FHashFunction(Item^.Key) mod Length(NewTable); // $R-
            Item^.Next := NewTable[Hash];
            NewTable[Hash] := Item;
            Item := NextItem;
         end;
      end;
      FTable := NewTable;
   end;
end;
      
function THashTable.InternalAdd(const Key: TKey): PHashTableEntry;
var
   Hash: DWord;
begin
   // see also similar code in GetOrAddPtr
   Assert(not Has(Key));
   Inc(FCount);
   if (FCount / Length(FTable) > kMaxLoadFactor) then
   begin
      { Wikipedia: "With a good hash function, the average lookup cost is nearly constant as the load factor increases from 0 up to 0.7 or so" }
      DoubleSize();
   end;
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Hash := FHashFunction(Key) mod Length(FTable); // $R-
   New(Result);
   Result^.Key := Key;
   Result^.Next := FTable[Hash];
   FTable[Hash] := Result;
end;

function THashTable.AddDefault(const Key: TKey): PValue;
begin
   Result := @(InternalAdd(Key)^.Value);
end;

procedure THashTable.Add(const Key: TKey; const Value: TValue);
begin
   InternalAdd(Key)^.Value := Value;
end;

procedure THashTable.Remove(const Key: TKey);
var
   Hash: DWord;
   Entry: PHashTableEntry;
   LastEntry: PPHashTableEntry;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Hash := FHashFunction(Key) mod Length(FTable); // $R-
   Entry := FTable[Hash];
   LastEntry := @FTable[Hash];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         LastEntry^ := Entry^.Next;
         Dispose(Entry);
         Dec(FCount);
         exit;
      end;
      LastEntry := @Entry^.Next;
      Entry := Entry^.Next;
   end;
end;

function THashTable.Get(const Key: TKey): TValue;
var
   Entry: PHashTableEntry;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Entry := FTable[FHashFunction(Key) mod Length(FTable)];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         Result := Entry^.Value;
         exit;
      end;
      Entry := Entry^.Next;
   end;
   Result := Default(TValue); // TODO: return a missing value from the Utils instead
end;

function THashTable.GetPtr(const Key: TKey): PValue;
var
   Entry: PHashTableEntry;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Entry := FTable[FHashFunction(Key) mod Length(FTable)];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         Result := @Entry^.Value;
         exit;
      end;
      Entry := Entry^.Next;
   end;
   Result := nil;
end;

function THashTable.GetOrAddPtr(const Key: TKey): PValue;
var
   Entry: PHashTableEntry;
   Hash: DWord;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Hash := FHashFunction(Key) mod Length(FTable); // $R-
   Entry := FTable[Hash];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         Result := @Entry^.Value;
         exit;
      end;
      Entry := Entry^.Next;
   end;
   // see InternalAdd
   Inc(FCount);
   if (FCount / Length(FTable) > kMaxLoadFactor) then
   begin
      { Wikipedia: "With a good hash function, the average lookup cost is nearly constant as the load factor increases from 0 up to 0.7 or so" }
      DoubleSize();
   end;
   New(Entry);
   Entry^.Key := Key;
   Entry^.Next := FTable[Hash];
   FTable[Hash] := Entry;
   Result := @Entry^.Value;
end;

function THashTable.Has(const Key: TKey): Boolean;
var
   Entry: PHashTableEntry;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Entry := FTable[FHashFunction(Key) mod Length(FTable)];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         Result := True;
         exit;
      end;
      Entry := Entry^.Next;
   end;
   Result := False;
end;

procedure THashTable.Update(const Key: TKey; const Value: TValue);
var
   Entry: PHashTableEntry;
begin
   { This is safe because Length(table) is positive and 'mod' will only ever return a smaller value }
   Entry := FTable[FHashFunction(Key) mod Length(FTable)];
   while (Assigned(Entry)) do
   begin
      if (Utils.Equals(Entry^.Key, Key)) then
      begin
         Entry^.Value := Value;
         exit;
      end;
      Entry := Entry^.Next;
   end;
   Add(Key, Value);
end;

{$IFDEF DEBUG}
procedure THashTable.Histogram(var F: Text);
var
   Index: THashTableSizeInt;
   Item: PHashTableEntry;
begin
   Assert(Length(FTable) > 0);
   Writeln(F, 'THashTable histogram:'); // $DFA- for F
   for Index := Low(FTable) to High(FTable) do // $R-
   begin
      System.Write(F, Index: 5, ': ');
      Item := FTable[Index];
      while (Assigned(Item)) do
      begin
         System.Write(F, '#');
         Item := Item^.Next;
      end;
      Writeln(F);
   end;
   Writeln(F, 'Size: ' + IntToStr(Length(FTable)) + '; Count: ' + IntToStr(FCount));
end;
{$ENDIF}

function THashTable.GetKeyForEntry(const Entry: Pointer): TKey;
begin
   if (Assigned(Entry)) then
   begin
      Result := PHashTableEntry(Entry)^.Key;
   end
   else
   begin
      Result := Default(TKey); // TODO: return a missing value from the Utils instead
   end;
end;

function THashTable.GetValueForEntry(const Entry: Pointer): TValue;
begin
   if (Assigned(Entry)) then
   begin
      Result := PHashTableEntry(Entry)^.Value;
   end
   else
   begin
      Result := Default(TValue); // TODO: return a missing value from the Utils instead
   end;
end;

function THashTable.GetValuePtrForEntry(const Entry: Pointer): PValue;
begin
   if (Assigned(Entry)) then
   begin
      Result := @(PHashTableEntry(Entry)^.Value);
   end
   else
   begin
      Result := nil;
   end;
end;

procedure THashTable.AdvanceEnumerator(var Current: Pointer; var Index: THashTableSizeInt);
begin
   if (Assigned(Current)) then
   begin // advance
      Current := PHashTableEntry(Current)^.Next;
   end
   else
   if (FCount > 0) then
   begin // just started
      Assert(Length(FTable) > 0);
      Assert(Index = 0);
      Current := FTable[Index];
   end;
   while ((not Assigned(Current)) and (Index < High(FTable))) do
   begin
      Inc(Index);
      Current := FTable[Index];
   end;
end;

procedure THashTable.RemoveEntry(Current: Pointer; Index: THashTableSizeInt);
var
   Entry: PHashTableEntry;
   LastEntry: PPHashTableEntry;
begin
   Assert(Assigned(Current));
   Entry := FTable[Index];
   LastEntry := @FTable[Index];
   while (Assigned(Entry)) do
   begin
      if (Entry = Current) then
      begin
         LastEntry^ := Entry^.Next;
         Dispose(Entry);
         Dec(FCount);
         exit;
      end;
      LastEntry := @Entry^.Next;
      Entry := Entry^.Next;
   end;
end;

function THashTable.Clone(): THashTable;
var
   Index: Cardinal;
   Current: PHashTableEntry;
begin
   Assert(Assigned(Self));
   Result := ClassType.Create() as THashTable;
   Result.FHashFunction := FHashFunction;
   Result.PrepareForSize(FCount);
   if (FCount > 0) then
   begin
      Assert(Length(FTable) > 0);
      for Index := Low(FTable) to High(FTable) do // $R-
      begin
         Current := FTable[Index];
         while (Assigned(Current)) do
         begin
            Result.Add(Current^.Key, Current^.Value);
            Current := Current^.Next;
         end;
      end;
   end;
   Assert(Result.Count = FCount);
end;


constructor THashTable.TKeyEnumerator.Create(const Owner: THashTable);
begin
   FOwner := Owner;
   FIndex := 0;
   FCurrent := nil;
end;

function THashTable.TKeyEnumerator.GetCurrent(): TKey;
begin
   Result := FOwner.GetKeyForEntry(FCurrent);
end;

function THashTable.TKeyEnumerator.GetCurrentValue(): TValue;
begin
   Result := FOwner.GetValueForEntry(FCurrent);
end;

function THashTable.TKeyEnumerator.MoveNext(): Boolean;
begin
   FOwner.AdvanceEnumerator(FCurrent, FIndex);
   Result := Assigned(FCurrent);
end;

function THashTable.TKeyEnumerator.GetEnumerator(): TKeyEnumerator;
begin
   Result := Self;
end;

function THashTable.GetEnumerator(): TKeyEnumerator;
begin
   Result := TKeyEnumerator.Create(Self);
end;


constructor THashTable.TValueEnumerator.Create(const Owner: THashTable);
begin
   FOwner := Owner;
   FIndex := 0;
   FCurrent := nil;
end;

function THashTable.TValueEnumerator.GetCurrent(): TValue;
begin
   Result := FOwner.GetValueForEntry(FCurrent);
end;

function THashTable.TValueEnumerator.MoveNext(): Boolean;
begin
   FOwner.AdvanceEnumerator(FCurrent, FIndex);
   Result := Assigned(FCurrent);
end;

function THashTable.TValueEnumerator.GetEnumerator(): TValueEnumerator;
begin
   Result := Self;
end;

function THashTable.Values(): TValueEnumerator;
begin
   Result := TValueEnumerator.Create(Self);
end;


constructor THashTable.TValuePtrEnumerator.Create(const Owner: THashTable);
begin
   FOwner := Owner;
   FIndex := 0;
   FCurrent := nil;
   FAlreadyAdvanced := False;
end;

function THashTable.TValuePtrEnumerator.GetCurrent(): PValue;
begin
   Assert(not FAlreadyAdvanced);
   Result := FOwner.GetValuePtrForEntry(FCurrent);
end;

function THashTable.TValuePtrEnumerator.GetCurrentKey(): TKey;
begin
   Assert(not FAlreadyAdvanced);
   Result := FOwner.GetKeyForEntry(FCurrent);
end;

function THashTable.TValuePtrEnumerator.MoveNext(): Boolean;
begin
   if (not FAlreadyAdvanced) then
      FOwner.AdvanceEnumerator(FCurrent, FIndex);
   Result := Assigned(FCurrent);
   FAlreadyAdvanced := False;
end;

procedure THashTable.TValuePtrEnumerator.RemoveCurrent();
var
   OldCurrent: Pointer;
   OldIndex: THashTableSizeInt;
begin
   Assert(not FAlreadyAdvanced);
   OldCurrent := FCurrent;
   OldIndex := FIndex;
   FOwner.AdvanceEnumerator(FCurrent, FIndex);
   FOwner.RemoveEntry(OldCurrent, OldIndex);
   FAlreadyAdvanced := True;
end;

function THashTable.TValuePtrEnumerator.GetEnumerator(): TValuePtrEnumerator;
begin
   Result := Self;
end;

function THashTable.ValuePtrs(): TValuePtrEnumerator;
begin
   Result := TValuePtrEnumerator.Create(Self);
end;


function THashTable.GetIsEmpty(): Boolean;
begin
   Result := Count = 0;
end;

function THashTable.GetIsNotEmpty(): Boolean;
begin
   Result := Count > 0;
end;

end.
