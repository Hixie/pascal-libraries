{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sharedpointer;

interface

type
   generic TSharedPointer <T{: class}> = record // restore constraint when https://gitlab.com/freepascal.org/fpc/source/-/issues/41497 is fixed
   private
      type
         SelfT = specialize TSharedPointer<T>;
      var
         FPointer: T;
         FRefCount: PCardinal;
      class procedure IncRef(var Self: SelfT); static; inline;
      class procedure DecRef(var Self: SelfT); static; inline;
      function GetAssigned(): Boolean; inline;
   public
      class operator Initialize(var Self: SelfT);
      class operator Finalize(var Self: SelfT);
      class operator AddRef(var Self: SelfT);
      class operator Copy(constref Source: SelfT; var Destination: SelfT);
      class operator :=(const Source: T): SelfT;
      procedure Free();
      property Value: T read FPointer;
      property Assigned: Boolean read GetAssigned;
   end;
   
   // Troubleshooting: Make sure not to assign the same pointer to two
   // different TSharedPointer instances. When creating the managed
   // value, assign it directly to a TSharedPointer, rather than to an
   // intermediate.

generic function CastSharedPointer<OldT: class; NewT: class>(Source: specialize TSharedPointer<OldT>): specialize TSharedPointer<NewT>;

type // for use in hashtables etc
   generic SharedPointerUtils<T: class> = record
      class function Equals(const A, B: specialize TSharedPointer<T>): Boolean; static; inline;
      class function LessThan(const A, B: specialize TSharedPointer<T>): Boolean; static; inline; unimplemented;
      class function GreaterThan(const A, B: specialize TSharedPointer<T>): Boolean; static; inline; unimplemented;
      class function Compare(const A, B: specialize TSharedPointer<T>): Int64; static; inline; unimplemented;
   end;

implementation

uses
   sysutils {$IFDEF VERBOSE}, exceptions {$ENDIF};

class procedure TSharedPointer.IncRef(var Self: SelfT);
begin
   Assert(system.Assigned(Self.FRefCount) = system.Assigned(Self.FPointer), 'Invariant violation: refcount and pointer are inconsistent in IncRef');
   if (system.Assigned(Self.FRefCount)) then
   begin
      InterlockedIncrement(Self.FRefCount^);
      {$IFDEF VERBOSE} Writeln('IncRef ', HexStr(Pointer(Self.FPointer)), ' to ', Self.FRefCount^, ' at ', HexStr(Self.FRefCount)); {$ENDIF}
   end;
end;

class procedure TSharedPointer.DecRef(var Self: SelfT);
begin
   {$IFDEF VERBOSE}
   if (Assigned(Self.FRefCount)) then
      Writeln('DecRef ', HexStr(Pointer(Self.FPointer)), ' to ', Self.FRefCount^ - 1, ' at ', HexStr(Self.FRefCount));
   {$ENDIF}
   if (system.Assigned(Self.FRefCount) and (InterlockedDecrement(Self.FRefCount^) = 0)) then
   begin
      FreeAndNil(Self.FPointer);
      Dispose(Self.FRefCount);
      Self.FRefCount := nil;
   end;
end;

function TSharedPointer.GetAssigned(): Boolean;
begin
   Result := system.Assigned(FPointer);
   Assert(Result = system.Assigned(FRefCount));
   Assert((not Result) or (FRefCount^ > 0));
end;

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
   IncRef(Self);
end;

class operator TSharedPointer.Copy(constref Source: SelfT; var Destination: SelfT);
begin
   DecRef(Destination);
   Assert(system.Assigned(Source.FRefCount) = system.Assigned(Source.FPointer), 'Invariant violation: Source refcount and pointer are inconsistent');
   if (system.Assigned(Source.FRefCount)) then
   begin
      InterlockedIncrement(Source.FRefCount^);
      {$IFDEF VERBOSE} Writeln('IncRef ', HexStr(Pointer(Source.FPointer)), ' to ', Source.FRefCount^, ' at ', HexStr(Source.FRefCount), ' (copy)'); {$ENDIF}
   end;
   Destination.FRefCount := Source.FRefCount;
   Destination.FPointer := Source.FPointer;
end;

class operator TSharedPointer.:=(const Source: T): SelfT;
begin
   DecRef(Result); // {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (system.Assigned(Source)) then
   begin
      New(Result.FRefCount);
      Result.FRefCount^ := 1;
      Result.FPointer := Source;
      {$IFDEF VERBOSE} Writeln('IncRef ', HexStr(Pointer(Result.FPointer)), ' to ', Result.FRefCount^, ' at ', HexStr(Result.FRefCount), ' (initial)'); {$ENDIF}
      {$IFDEF VERBOSE} Writeln(GetStackTrace()); {$ENDIF}
   end
   else
   begin
      Result.FRefCount := nil;
      Result.FPointer := nil;
   end;
end;

procedure TSharedPointer.Free();
begin
   DecRef(Self);
   FPointer := nil;
   FRefCount := nil;
end;


generic function CastSharedPointer<OldT; NewT>(Source: specialize TSharedPointer<OldT>): specialize TSharedPointer<NewT>;
begin
   specialize TSharedPointer<NewT>.DecRef(Result); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   Result.FPointer := Source.FPointer;
   Result.FRefCount := Source.FRefCount;
   specialize TSharedPointer<NewT>.IncRef(Result);
end;


class function SharedPointerUtils.Equals(const A, B: specialize TSharedPointer<T>): Boolean;
begin
   Result := A.FPointer = B.FPointer;
end;

class function SharedPointerUtils.LessThan(const A, B: specialize TSharedPointer<T>): Boolean;
begin
   raise Exception.Create('unimplemented');
end;

class function SharedPointerUtils.GreaterThan(const A, B: specialize TSharedPointer<T>): Boolean;
begin
   raise Exception.Create('unimplemented');
end;

class function SharedPointerUtils.Compare(const A, B: specialize TSharedPointer<T>): Int64;
begin
   raise Exception.Create('unimplemented');
end;

end.
