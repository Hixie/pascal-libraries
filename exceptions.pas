{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit exceptions;

interface

uses
   sysutils, baseunix;

type
   EKernelError = class(Exception)
      constructor Create(AErrorCode: cint);
   end;
   ESocketError = class(Exception)
      constructor Create(AErrorCode: cint);
   end;
   ESyntaxError = class(Exception)
   end;
   ECaughtException = class end;

   TReportExceptionEvent = procedure(E: Exception) of object;

procedure ReportCurrentException();
procedure ReportException(E: Exception);
procedure ReportExceptionAndFree(E: Exception); { for unraised exceptions }
function SetReportExceptionMethod(AReportExceptionMethod: TReportExceptionEvent): TReportExceptionEvent;

type
   TXXX = record end unimplemented;

function XXX: Variant; unimplemented;

{$IFDEF DEBUG} function GetStackTrace(): AnsiString; {$ENDIF}

implementation

uses
   errors;

const
   KernelErrorMsg: String = 'kernel error %d: %s';
   SocketErrorMsg: String = 'socket error %d: %s';

var
   ReportExceptionMethod: TReportExceptionEvent = nil;

constructor EKernelError.Create(AErrorCode: cint);
begin
   inherited Create(Format(KernelErrorMsg, [AErrorCode, StrError(AErrorCode)]));
end;

constructor ESocketError.Create(AErrorCode: cint);
begin
   inherited Create(Format(SocketErrorMsg, [AErrorCode, StrError(AErrorCode)]));
end;

procedure WriteBacktrace(Address: Pointer; Frames: PPointer; FrameCount: Integer);
var
   FrameNumber: Cardinal;
begin
   Writeln('Backtrace:');
   if (Address = nil) then
      Writeln('  dereferenced nil pointer')
   else
      Writeln(BackTraceStrFunc(Address));
   if (FrameCount > 0) then
      for FrameNumber := 0 to FrameCount-1 do {BOGUS Warning: Type size mismatch, possible loss of data / range check error}
         Writeln(BackTraceStrFunc(Frames[FrameNumber]));
end;

procedure ReportCurrentException();
begin
   Assert(Assigned(RaiseList));
   Assert(Assigned(RaiseList^.FObject));
   if (RaiseList^.FObject is Exception) then
      Writeln(RaiseList^.FObject.ClassName, ' exception: ', (RaiseList^.FObject as Exception).Message)
   else
      Writeln(RaiseList^.FObject.ClassName, ' exception');
   WriteBacktrace(RaiseList^.Addr, RaiseList^.Frames, RaiseList^.FrameCount);
end;

procedure ReportException(E: Exception);
begin
   Assert((not Assigned(RaiseList)) or (not Assigned(RaiseList^.FObject)) or (RaiseList^.FObject <> E), 'Inside an exception handler, use ReportCurrentException() to get the right stack trace');
   if (Assigned(ReportExceptionMethod)) then
      ReportExceptionMethod(E)
   else
   begin
      Writeln(E.Message);
      Dump_Stack(Output, Get_Frame);
   end;
end;

procedure ReportExceptionAndFree(E: Exception);
begin
   ReportException(E);
   E.Free();
end;

function SetReportExceptionMethod(AReportExceptionMethod: TReportExceptionEvent): TReportExceptionEvent;
begin
   Result := ReportExceptionMethod;
   ReportExceptionMethod := AReportExceptionMethod;
end;

{$WARNINGS OFF}
function XXX: Variant;
begin
   //Assert(False, 'Not Implemented');
   raise Exception.Create('Not Implemented') at get_caller_addr(get_frame), get_caller_frame(get_frame);  
end;
{$WARNINGS ON}

procedure AssertionHandler(const Message, FileName: ShortString; LineNo: Longint; ErrorAddr: Pointer);
var
   CompleteMessage: AnsiString;
begin
   if (Message <> '') then
      CompleteMessage := 'Assertion "' + Message + '" failed on line ' + IntToStr(LineNo) + ' of ' + FileName
   else
      CompleteMessage := 'Assertion failed on line ' + IntToStr(LineNo) + ' of ' + FileName;
   {$IFDEF DEBUG}
   Writeln('Raising assertion: ', CompleteMessage);
   {$ENDIF}
   raise EAssertionFailed.Create(CompleteMessage) at Get_Caller_Addr(ErrorAddr), Get_Caller_Frame(ErrorAddr);
end;

{$IFDEF DEBUG}
function GetStackTrace(): AnsiString;
// the following is a verbatim copy from http://wiki.freepascal.org/Logging_exceptions
var
  I: Longint;
  prevbp: Pointer;
  CallerFrame,
  CallerAddress,
  bp: Pointer;
  Report: string;
const
  MaxDepth = maxint;
begin
  Report := '';
  bp := get_frame;
  // This trick skip SendCallstack item
  // bp:= get_caller_frame(get_frame);
  try
    prevbp := bp - 1;
    I := 0;
    while bp > prevbp do begin
       CallerAddress := get_caller_addr(bp);
       CallerFrame := get_caller_frame(bp);
       if (CallerAddress = nil) then
         Break;
       Report := Report + BackTraceStrFunc(CallerAddress) + LineEnding;
       Inc(I);
       if (I >= MaxDepth) or (CallerFrame = nil) then
         Break;
       prevbp := bp;
       bp := CallerFrame;
     end;
   except
     { prevent endless dump if an exception occured }
   end;
   // end of copy from http://wiki.freepascal.org/Logging_exceptions
   Result := Report;
end;
{$ENDIF}

initialization
   {$IFDEF DEBUG} AssertErrorProc := @AssertionHandler; {$ENDIF}
end.
