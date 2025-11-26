{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit unixutils;

interface

uses
   unixtype;

// Process manipulation

type
   TProcess = class
   private
      FPid: TPid;
      FOutputFD: cint;
   public
      constructor Create(APid: TPid; AOutput: cint);
      destructor Destroy(); override;
      procedure Signal(Code: cint);
      procedure Close(Timeout: Int64 = -1); // sends SIGTERM, then, if necessary, Timeout milliseconds later, SIGKILL.
      function ReadSomeOutput(Timeout: Int64 = -1): UTF8String; // reads at least one byte (unless timeout expires)
      function ReadAllRemainingOutput(): UTF8String;
      class function Start(const Executable: UTF8String; Arguments: array of UTF8String): TProcess;
      property ProcessID: TPid read FPid;
      property OutputFD: cint read FOutputFD;
   end;

function fpPidFdOpen(Pid: TPid; Flags: cuint = 0): cint;

const
   fdStdin = 0;
   fdStdout = 1;
   fdStderr = 2;

// Signal handling
// Consider sigint.pas if all you need is ^C handling.
   
var
   Aborted: Boolean = False;
   
procedure HookSignalHandlers();

// Page allocations

function GetPageSize(): PtrUInt; inline;
function AllocPage(): Pointer;
procedure FreePage(var Page: Pointer);

// Auxiliary Vector

const // from auxvec.h
   AT_IGNORE = 1; // entry should be ignored
   AT_EXECFD = 2; // file descriptor of program
   AT_PHDR = 3; // program headers for program
   AT_PHENT = 4; // size of program header entry
   AT_PHNUM = 5; // number of program headers
   AT_PAGESZ = 6; // system page size
   AT_BASE = 7; // base address of interpreter
   AT_FLAGS = 8; // flags
   AT_ENTRY = 9; // entry point of program
   AT_NOTELF = 10; // program is not ELF
   AT_UID = 11; // real uid
   AT_EUID = 12; // effective uid
   AT_GID = 13; // real gid
   AT_EGID = 14; // effective gid
   AT_PLATFORM = 15; // string identifying CPU for optimizations
   AT_HWCAP = 16; // arch dependent hints at CPU capabilities
   AT_CLKTCK = 17; // frequency at which times() increments
   AT_SECURE = 23; // secure mode boolean
   AT_BASE_PLATFORM = 24; // string identifying real platform, may differ from AT_PLATFORM
   AT_RANDOM = 25; // address of 16 random bytes
   AT_EXECFN = 31; // filename of program

function GetAuxilliaryVectorValue(Code: PtrUInt): PtrUInt;

implementation

uses
   sysutils, baseunix, exceptions, syscall;

const
   KB = 1024;
   MB = 1024 * KB;

constructor TProcess.Create(APid: TPid; AOutput: cint);
begin
   inherited Create();
   FPid := APid;
   FOutputFD := AOutput;
end;

destructor TProcess.Destroy();
begin
   fpClose(FOutputFD);
   inherited;
end;

procedure TProcess.Signal(Code: cint);
begin
   fpKill(FPid, Code);
end;

procedure TProcess.Close(Timeout: Int64 = -1);
var
   FileDescriptor: cint;
   FileDescriptors: PPollFd;
   PollResult: cint;
begin
   Signal(SIGTERM);
   FileDescriptor := fpPidFdOpen(FPid);
   if (FileDescriptor < 0) then
      raise EKernelError.Create(fpGetErrNo);
   New(FileDescriptors);
   FileDescriptors^.FD := FileDescriptor;
   FileDescriptors^.Events := POLLIN;
   FileDescriptors^.REvents := 0;
   try
      PollResult := fpPoll(FileDescriptors, 1, Timeout);
      if (PollResult = 0) then
         Signal(SIGKILL);
   finally
      Dispose(FileDescriptors);
   end;
end;

function TProcess.ReadSomeOutput(Timeout: Int64 = -1): UTF8String;
const
   BufferSize = 4 * KB;
var
   FileDescriptors: PPollFd;
   PollResult: cint;
   BytesRead: TSSize;
begin
   Result := '';
   SetLength(Result, BufferSize);
   New(FileDescriptors);
   FileDescriptors^.FD := FOutputFD;
   FileDescriptors^.Events := POLLIN;
   FileDescriptors^.REvents := 0;
   try
      PollResult := fpPoll(FileDescriptors, 1, Timeout);
      if (PollResult < 0) then
         raise EKernelError.Create(fpGetErrNo);
      if (PollResult = 0) then
      begin
         Result := '';
      end
      else
      begin
         BytesRead := fpRead(FOutputFD, Result[1], Length(Result)); // $R-
         if (BytesRead < 0) then
            raise EKernelError.Create(fpGetErrNo);
         SetLength(Result, BytesRead);
      end;
   finally
      Dispose(FileDescriptors);
   end;
end;

function TProcess.ReadAllRemainingOutput(): UTF8String;
const
   BufferSize = 1024; // read 1KB at a time
var
   Buffer: Pointer;
   Destination: Cardinal;
   BytesRead: TSSize;
begin
   Result := '';
   Buffer := GetMem(BufferSize);
   try
      repeat
         BytesRead := fpRead(FOutputFD, Buffer, BufferSize); // this is an expensive copy
         if (BytesRead < 0) then
            raise EKernelError.Create(fpGetErrNo);
         if (BytesRead > 0) then
         begin
            Destination := Length(Result) + 1; // $R-
            SetLength(Result, Length(Result) + BytesRead); // this might do an expensive copy
            Move(Buffer^, Result[Destination], BytesRead); // this is an expensive copy
         end;
      until BytesRead = 0;
   finally
      FreeMem(Buffer);
   end;
end;

class function TProcess.Start(const Executable: UTF8String; Arguments: array of UTF8String): TProcess;
var
   Child: TPid;
   Index: Cardinal;
   ChildPath: PChar;
   ChildArgV: PPChar;
   ChildEnvP: PPChar;
   FileDescriptors: TFilDes;
   ErrorResult: cint;
begin
   FileDescriptors[0] := 0;
   FileDescriptors[1] := 0;
   ErrorResult := fpPipe(FileDescriptors);
   if (ErrorResult <> 0) then
      raise EKernelError.Create(ErrorResult);
   Child := fpFork();
   if (Child < 0) then
      raise EKernelError.Create(fpGetErrNo);
   if (Child = 0) then
   begin
      ChildPath := PChar(Executable);
      ChildArgV := GetMem((Length(Arguments) + 2) * SizeOf(PChar)); // $R-
      ChildArgV[0] := ChildPath;
      for Index := Low(Arguments) to High(Arguments) do // $R-
         ChildArgV[Index + 1] := PChar(Arguments[Index]);
      ChildArgV[Length(Arguments) + 1] := nil;
      ChildEnvP := EnvP; // from system unit
      fpClose(FileDescriptors[0]);
      ErrorResult := FpFcntl(FileDescriptors[1], F_SETPIPE_SZ, 1 * MB);
      if (ErrorResult < 0) then
         raise EKernelError.Create(fpGetErrNo);
      fpDup2(FileDescriptors[1], fdStdout);
      fpDup2(FileDescriptors[1], fdStderr);
      fpClose(FileDescriptors[1]);
      fpExecVe(ChildPath, ChildArgV, ChildEnvP);
      // if we get here, fpExecVe failed
      raise EKernelError.Create(fpGetErrNo);
   end;
   Assert(Child > 0);
   fpClose(FileDescriptors[1]);
   Result := TProcess.Create(Child, FileDescriptors[0]);
   Assert(Assigned(Result));
end;


procedure SigIntHandler(Signal: Longint; Info: PSigInfo; Context: PSigContext); cdecl;
begin
   {$IFDEF DEBUG}
     Writeln();
     Writeln('caught ^C; aborting at:');
     Writeln(GetStackTrace());
     Writeln();
   {$ENDIF}
   Aborted := True;
end;

procedure SigTermHandler(Signal: Longint; Info: PSigInfo; Context: PSigContext); cdecl;
begin
   {$IFDEF DEBUG}
     Writeln();
     Writeln('caught SIGTERM; aborting at:');
     Writeln(GetStackTrace());
     Writeln();
   {$ENDIF}
   Aborted := True;
end;

procedure SigPipeHandler(Signal: Longint; Info: PSigInfo; Context: PSigContext); cdecl;
begin
   {$IFDEF DEBUG}
     Writeln();
     Writeln('caught SIGPIPE; aborting at:');
     Writeln(GetStackTrace());
     Writeln();
   {$ENDIF}
   Aborted := True;
end;

function fpPidFdOpen(Pid: TPid; Flags: cuint = 0): cint;
begin
   Result := Do_SysCall(syscall_nr_pidfd_open, Pid, Flags); // $R-
end;

procedure HookSignalHandlers();
var
   NewAction: PSigActionRec;
begin
   New(NewAction);
   if (not Assigned(NewAction)) then
      OutOfMemoryError();
   try
      {$IFDEF Linux} NewAction^.sa_restorer := nil; {$ENDIF}
      FillByte(NewAction^.sa_mask, SizeOf(NewAction^.sa_mask), 0);

      // SIGINT - one-off handler
      NewAction^.sa_handler := @SigIntHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      if (fpSigAction(SIGINT, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);

      // SIGTERM - one-off handler
      NewAction^.sa_handler := @SigTermHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      if (fpSigAction(SIGTERM, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);

      // SIGPIPE - one-off handler
      NewAction^.sa_handler := @SigPipeHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      if (fpSigAction(SIGPIPE, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);

   finally
      Dispose(NewAction);
   end;
end;

var
   PageSize: PtrUInt;

function GetPageSize(): PtrUInt;
begin
   Result := PageSize;
end;

function AllocPage(): Pointer;
begin
   Result := fpMMap(nil, PageSize, PROT_READ or PROT_WRITE, MAP_PRIVATE or MAP_ANONYMOUS, -1, 0);
   if (Result = MAP_FAILED) then
      raise EKernelError.Create(fpGetErrNo);
end;

procedure FreePage(var Page: Pointer);
begin
   if (fpMUnmap(Page, PageSize) <> 0) then
      raise EKernelError.Create(fpGetErrNo);
   Page := nil;
end;

function GetAuxilliaryVectorValue(Code: PtrUInt): PtrUInt;
var
   AuxiliaryVector: PPointer;
begin
   // Linux puts the Auxiliary Vector after the Environment Table, a pointer to which FreePascal puts in EnvP.
   AuxiliaryVector := PPointer(EnvP);
   while (Assigned(AuxiliaryVector^)) do
      Inc(AuxiliaryVector);
   Inc(AuxiliaryVector);
   // AuxiliaryVector now points to the top of the Auxiliary Vector.
   Result := 0;
   while (Assigned(AuxiliaryVector^)) do
   begin
      if (PtrUInt(AuxiliaryVector^) = Code) then
      begin
         Inc(AuxiliaryVector);
         Result := PtrUInt(AuxiliaryVector^);
         break;
      end;
      Inc(AuxiliaryVector, 2);
   end;
end;

initialization
   PageSize := GetAuxilliaryVectorValue(AT_PAGESZ);
end.