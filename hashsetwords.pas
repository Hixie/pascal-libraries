{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit hashsetwords;

// This exposes the same API as TTightHashSet<T, specialize TTightHashUtils16<T>>, but when the
// set contains three or fewer values, the data is stored in the pointer itself, rather than
// allocating an entire hash set.
//
// T must be 16 bits wide (a Word). Values FFFE and FFFF are reserved.

interface

uses
   hashsettight;

type
   generic TWordHashSet<T> = record
   strict private
      type
         TBackingSet = specialize TTightHashSet<T, specialize TTightHashUtils16<T>>;
      var
         FData: PtrUInt; // raw data, or TBackingSet
         // The raw data is stored as follows:
         //    AAAA BBBB CCCC FFFF
         // ...where AAAA, BBBB, and CCCC are three values in the set.
         // Any missing values are stored as FFFF.
         // If the low bit is zero, then this a TBackingSet.
      class operator Initialize(var Rec: TWordHashSet);
      class operator Finalize(var Rec: TWordHashSet);
      class operator AddRef(var Rec: TWordHashSet); // throws
      class operator Copy(constref Source: TWordHashSet; var Destination: TWordHashSet); // throws
      function GetCount(): Word;
      function GetIsEmpty(): Boolean;
      function GetIsNotEmpty(): Boolean;
    public
      procedure Reset(); // empty the set
      procedure Add(const Value: T);
      procedure Remove(const Value: T);
      function Has(const Value: T): Boolean;
      property Count: Word read GetCount;
      property IsEmpty: Boolean read GetIsEmpty;
      property IsNotEmpty: Boolean read GetIsNotEmpty;
      procedure CloneTo(var Output: TWordHashSet);
      procedure MoveTo(var Output: TWordHashSet);
    public
     type
       TEnumerator = class
       strict private
          FBackingEnumerator: TBackingSet.TEnumerator;
          FData: PtrUInt; // the zero to three values being enumerated
          function GetCurrent(): T;
       public
          constructor Create(const Owner: TWordHashSet);
          destructor Destroy(); override;
          function MoveNext(): Boolean;
          property Current: T read GetCurrent;
          function GetEnumerator(): TEnumerator;
       end;
      function GetEnumerator(): TEnumerator;
   end;

implementation

uses
   sysutils;

class operator TWordHashSet.Initialize(var Rec: TWordHashSet);
begin
   Rec.FData := PtrUInt($FFFFFFFFFFFFFFFF);
end;

class operator TWordHashSet.Finalize(var Rec: TWordHashSet);
begin
   if (Rec.FData and 1) = 0 then
      FreeAndNil(TBackingSet(Pointer(Rec.FData))); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
end;

class operator TWordHashSet.AddRef(var Rec: TWordHashSet);
begin
   raise Exception.Create('TWordHashSet cannot be copied.');
end;

class operator TWordHashSet.Copy(constref Source: TWordHashSet; var Destination: TWordHashSet);
begin
   raise Exception.Create('TWordHashSet cannot be copied.');
end;

function TWordHashSet.GetCount(): Word;
begin
   if ((FData and $0001) = $0000) then
   begin
      Result := TBackingSet(Pointer(FData)).Count; // {BOGUS Hint: Conversion between ordinals and pointers is not portable} // $R-
   end
   else
   begin
      Result := 0;
      if (Word(FData shr 48) <> $FFFF) then
         Inc(Result);
      if (Word(FData shr 32) <> $FFFF) then
         Inc(Result);
      if (Word(FData shr 16) <> $FFFF) then
         Inc(Result);
   end;
end;

function TWordHashSet.GetIsEmpty(): Boolean;
begin
   if ((FData and $0001) = $0000) then
   begin
      Result := TBackingSet(Pointer(FData)).IsEmpty; // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Result := FData = PtrUInt($FFFFFFFFFFFFFFFF);
   end;
end;

function TWordHashSet.GetIsNotEmpty(): Boolean;
begin
   if ((FData and $0001) = $0000) then
   begin
      Result := TBackingSet(Pointer(FData)).IsNotEmpty; // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Result := FData <> PtrUInt($FFFFFFFFFFFFFFFF);
   end;
end;

procedure TWordHashSet.Reset();
begin
   if ((FData and $0001) = $0000) then
      TBackingSet(Pointer(FData)).Reset() // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   else
      FData := PtrUInt($FFFFFFFFFFFFFFFF);
   Assert(IsEmpty);
end;

procedure TWordHashSet.Add(const Value: T);
var
   BackingSet: TBackingSet;
begin
   if ((FData and $0001) = $0000) then
   begin
      // Proxy to backing set
      TBackingSet(Pointer(FData)).Add(Value); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Assert(not Has(Value));
      // Find highest word that is $FFFF
      if (Word(FData shr 48) = $FFFF) then
      begin
         FData := (FData and $0000FFFFFFFFFFFF) or (PtrUInt(Word(Value)) shl 48);
      end
      else
      if (Word(FData shr 32) = $FFFF) then
      begin
         FData := (FData and $FFFF0000FFFFFFFF) or (PtrUInt(Word(Value)) shl 32);
      end
      else
      if (Word(FData shr 16) = $FFFF) then
      begin
         FData := (FData and $FFFFFFFF0000FFFF) or (PtrUInt(Word(Value)) shl 16);
      end
      else
      begin
         // All three slots are full, need to allocate backing set
         BackingSet := TBackingSet.Create();
         BackingSet.Add(T(Word((FData shr 48) and $FFFF)));
         BackingSet.Add(T(Word((FData shr 32) and $FFFF)));
         BackingSet.Add(T(Word((FData shr 16) and $FFFF)));
         BackingSet.Add(Value);
         FData := PtrUInt(Pointer(BackingSet));
      end;
   end;
end;

procedure TWordHashSet.Remove(const Value: T);
begin
   if ((FData and $0001) = $0000) then
   begin
      TBackingSet(Pointer(FData)).Remove(Value); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Assert(Has(Value));
      if (Word((FData shr 48) and $FFFF) = Word(Value)) then
      begin
         FData := FData or PtrUInt($FFFF000000000000);
      end
      else
      if (Word((FData shr 32) and $FFFF) = Word(Value)) then
      begin
         FData := FData or PtrUInt($0000FFFF00000000);
      end
      else
      if (Word((FData shr 16) and $FFFF) = Word(Value)) then
      begin
         FData := FData or PtrUInt($00000000FFFF0000);
      end
      else
         raise Exception.Create('Remove was called with a value that is not in the set.');
   end;
end;

function TWordHashSet.Has(const Value: T): Boolean;
begin
   if ((FData and $0001) = $0000) then
   begin
      Result := TBackingSet(Pointer(FData)).Has(Value); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Result := (Word((FData shr 48) and $FFFF) = Word(Value))
             or (Word((FData shr 32) and $FFFF) = Word(Value))
             or (Word((FData shr 16) and $FFFF) = Word(Value));
   end;
end;

procedure TWordHashSet.CloneTo(var Output: TWordHashSet);
begin
   Finalize(Output);
   if ((FData and $0001) = $0000) then
   begin
      Output.FData := PtrUInt(Pointer(TBackingSet(Pointer(FData)).Clone()));
   end
   else
   begin
      Output.FData := FData;
   end;
end;

procedure TWordHashSet.MoveTo(var Output: TWordHashSet);
begin
   Finalize(Output);
   Output.FData := FData;
   FData := PtrUInt($FFFFFFFFFFFFFFFF);
end;


constructor TWordHashSet.TEnumerator.Create(const Owner: TWordHashSet);
begin
   inherited Create();
   if ((Owner.FData and $0001) = $0000) then
   begin
      FBackingEnumerator := TBackingSet(Pointer(Owner.FData)).GetEnumerator(); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end
   else
   begin
      Assert(not Assigned(FBackingEnumerator));
      FData := Owner.FData;
   end;
end;

destructor TWordHashSet.TEnumerator.Destroy();
begin
   FreeAndNil(FBackingEnumerator);
   inherited;
end;

function TWordHashSet.TEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FBackingEnumerator)) then
   begin
      Result := FBackingEnumerator.MoveNext();
   end
   else
   begin
      while (FData <> PtrUInt($FFFFFFFFFFFFFFFF)) do
      begin
         FData := (FData shr 16) or PtrUInt($FFFF000000000000);
         if (Word(FData and $FFFF) <> $FFFF) then
         begin
            Result := True;
            exit;
         end;
      end;
      Result := False;
   end;
end;

function TWordHashSet.TEnumerator.GetCurrent(): T;
begin
   if (Assigned(FBackingEnumerator)) then
      Result := FBackingEnumerator.Current // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   else
      Result := T(Word(FData and $FFFF));
end;

function TWordHashSet.TEnumerator.GetEnumerator(): TEnumerator;
begin
   Result := Self;
end;

function TWordHashSet.GetEnumerator(): TEnumerator;
begin
   if (IsEmpty) then
   begin
      Result := nil;
   end
   else
   begin
      Result := TEnumerator.Create(Self);
   end;
end;

end.
