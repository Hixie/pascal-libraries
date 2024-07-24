{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sharedpointer;

interface

type
   generic TSharedPointer <T: class> = record
   private
      type
         SelfT = specialize TSharedPointer<T>;
      var
         FPointer: T;
         FRefCount: PCardinal;
      class procedure DecRef(var Self: SelfT); static;
   public
      class operator Initialize(var Self: SelfT);
      class operator Finalize(var Self: SelfT);
      class operator AddRef(var Self: SelfT);
      class operator Copy(constref Source: SelfT; var Destination: SelfT);
      class operator :=(const Source: T): SelfT;
      procedure Free();
      property Value: T read FPointer;
   end;

implementation

uses
   sysutils;

class operator TSharedPointer.Initialize(var Self: SelfT);
begin
   Self.FPointer := nil;
   Self.FRefCount := nil;
end;

class operator TSharedPointer.Finalize(var Self: SelfT);
begin
   DecRef(Self);
end;

class operator TSharedPointer.AddRef(var Self: SelfT);
begin
   Assert(Assigned(Self.FRefCount) = Assigned(Self.FPointer), 'Invariant violation: refcount and pointer are inconsistent in AddRef');
   if (Assigned(Self.FRefCount)) then
      InterlockedIncrement(Self.FRefCount^);
end;

class operator TSharedPointer.Copy(constref Source: SelfT; var Destination: SelfT);
begin
   DecRef(Destination);
   Assert(Assigned(Source.FRefCount) = Assigned(Source.FPointer), 'Invariant violation: Source refcount and pointer are inconsistent');
   if (Assigned(Source.FRefCount)) then
      InterlockedIncrement(Source.FRefCount^);
   Destination.FRefCount := Source.FRefCount;
   Destination.FPointer := Source.FPointer;
end;

class operator TSharedPointer.:=(const Source: T): SelfT;
begin
   DecRef(Result); // {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (Assigned(Source)) then
   begin
      New(Result.FRefCount);
      Result.FRefCount^ := 1;
      Result.FPointer := Source;
   end
   else
   begin
      Result.FRefCount := nil;
      Result.FPointer := nil;
   end;
end;

class procedure TSharedPointer.DecRef(var Self: SelfT);
begin
   if (Assigned(Self.FRefCount) and (InterlockedDecrement(Self.FRefCount^) = 0)) then
   begin
      FreeAndNil(Self.FPointer);
      Dispose(Self.FRefCount);
      Self.FRefCount := nil;
   end;
end;

procedure TSharedPointer.Free();
begin
   DecRef(Self);
   FPointer := nil;
   FRefCount := nil;
end;

end.
