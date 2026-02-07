{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit hashsetwords;

// This exposes the same API as TTightHashSet<T, specialize TTightHashUtils16<T>>, but when the
// set contains three or fewer values, the data is stored in the pointer itself, rather than
// allocating an entire hash set.
//
// T must be 16 bits wide (a Word). Values FFFE and FFFF are reserved.

interface

type
   generic TWordHashSet<T> = record
   strict private
      type
         TBackingSet = TTightHashSet<T, specialize TTightHashUtils16<T>>;
      var
         FData: PtrUInt; // raw data, or TBackingSet
         // The raw data is stored as follows:
         //    AAAA BBBB CCCC FFFF
         // ...where AAAA, BBBB, and CCCC are three values in the set.
         // Any missing values are stored as FFFF.
         // If the low bit is zero, then this a TBackingSet.
      class operator Initialize(var Rec: TWordHashSet);
      class operator Finalize(var Rec: TWordHashSet);
    public
      procedure Reset(); // empty the set
      procedure Add(const Value: T);
      procedure Remove(const Value: T);
      function Has(const Value: T): Boolean;
      property Count: Word read FCount;
      property IsEmpty: Boolean read GetIsEmpty;
      property IsNotEmpty: Boolean read GetIsNotEmpty;
    public
     type
       TEnumerator = class
       strict private
          FBackingEnumerator: TBackingSet.TEnumerator;
          FData: PtrUInt; // the zero to three values being enumerated
          function GetCurrent(): T;
        public
          constructor Create(const Owner: TWordHashSet);
          function MoveNext(): Boolean;
          property Current: T read GetCurrent;
          function GetEnumerator(): TEnumerator;
       end;
      function GetEnumerator(): TEnumerator;
   end;

   generic TObjectSet<T: class> = class (specialize TTightHashSet<T, TTightHashUtilsPtr>) end;
   generic TInterfaceSet<T> = class (specialize TTightHashSet<T, TTightHashUtilsPtr>) end;

implementation

class operator TWordHashSet.Initialize(var Rec: TWordHashSet);
begin
   Rec.FData := PtrUInt($FFFFFFFFFFFFFFFF);
end;

class operator TWordHashSet.Finalize(var Rec: TWordHashSet);
begin
   if (Rec.FData and 1) = 0 then
      FreeAndNil(TBackingSet(Pointer(Rec.FData)));
end;

procedure TWordHashSet.Reset();
begin
   if ((FData and $0001) = $0000) then
      TBackingSet(Pointer(FData)).Reset()
   else
      FData := PtrUInt($FFFFFFFFFFFFFFFF);
end;

procedure TWordHashSet.Add(const Value: T);
var
   BackingSet: TBackingSet;
   Index: Integer;
begin
   if ((FData and $0001) = $0000) then
   begin
      // Proxy to backing set
      TBackingSet(Pointer(FData)).Add(Value);
   end
   else
   begin
      Assert(not Has(Value));
      // Find highest word that is $FFFF
      if Word(FData shr 48) = $FFFF then
      begin
         FData := (FData and $0000FFFFFFFFFFFF) or (PtrUInt(Word(Value)) shl 48);
      end
      else
      if Word(FData shr 32) = $FFFF then
      begin
         FData := (FData and $FFFF0000FFFFFFFF) or (PtrUInt(Word(Value)) shl 32);
      end
      else
      if Word(FData shr 16) = $FFFF then
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
var
   Index: Integer;
   TempData: PtrUInt;
begin
   if ((FData and $0001) = $0000) then
   begin
      TBackingSet(Pointer(FData)).Remove(Value);
   end
   else
   begin
      Assert(not Has(Value));
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
   end;
end;

function TWordHashSet.Has(const Value: T): Boolean;
var
   Index: Integer;
begin
   if ((FData and $0001) = $0000) then
   begin
      Result := TBackingSet(Pointer(FData)).Has(Value);
   end
   else
   begin
      Result := (Word((FData shr 48) and $FFFF) = Word(Value))
             or (Word((FData shr 32) and $FFFF) = Word(Value))
             or (Word((FData shr 16) and $FFFF) = Word(Value));
   end;
end;


constructor TWordHashSet.TEnumerator.Create(const Owner: TWordHashSet);
begin
   inherited Create();
   if ((FData and $0001) = $0000) then
   begin
      FBackingEnumerator := TBackingSet(Pointer(FData)).GetEnumerator();
   end
   else
   begin
      FData := Owner.FData;
   end;
end;

function TWordHashSet.TEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FBackingEnumerator)) then
   begin
      Result := FBackingEnumerator.MoveNext()
   end
   else
   begin
      if (FData = PtrUInt($FFFFFFFFFFFFFFFF)) then
      begin
         Result := False;
      end
      else
      begin
         FData := (FData shr 16) or PtrUInt($FFFF000000000000);
         Result := Word(FData and $FFFF) <> $FFFF;
      end;
   end;
end;

function TWordHashSet.TEnumerator.GetCurrent(): T;
begin
   if (Assigned(FBackingEnumerator)) then
      Result := FBackingEnumerator.GetCurrent()
   else
      Result := T(Word(FData and $FFFF));
end;

function TWordHashSet.TEnumerator.GetEnumerator(): TEnumerator;
begin
   Result := Self;
end;

function TWordHashSet.GetEnumerator(): TEnumerator;
begin
   Result := TEnumerator.Create(Self);
end;

end.
