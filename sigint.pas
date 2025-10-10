{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sigint;

interface

uses sysutils, baseunix, exceptions;

// Consider unixutils.pas if you need SIGPIPE handling also.
var
   Aborted: Boolean = False;

procedure InstallAbortHandler(); // listens for SIGINT and SIGTERM

implementation

procedure AbortHandler(Signal: Longint; Info: PSigInfo; Context: PSigContext); cdecl;
begin
   Aborted := True;
end;

procedure InstallAbortHandler();
var
   NewAction: PSigActionRec;
begin
   New(NewAction);
   if (not Assigned(NewAction)) then
      OutOfMemoryError();
   try
      {$IFDEF Linux} NewAction^.sa_restorer := nil; {$ENDIF}
      FillByte(NewAction^.sa_mask, SizeOf(NewAction^.sa_mask), 0);

      NewAction^.sa_handler := @AbortHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      if (fpSigAction(baseunix.SIGINT, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);

      NewAction^.sa_handler := @AbortHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      if (fpSigAction(baseunix.SIGTERM, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);
   finally
      Dispose(NewAction);
   end;
end;

end.