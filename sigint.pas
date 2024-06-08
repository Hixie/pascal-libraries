{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sigint;

interface

uses sysutils, baseunix, exceptions;

var
   Aborted: Boolean = False;

procedure InstallSigIntHandler();

implementation

procedure SigIntHandler(Signal: Longint; Info: PSigInfo; Context: PSigContext); cdecl;
begin
   Aborted := True;
end;

procedure InstallSigIntHandler();
var
   NewAction: PSigActionRec;
begin
   New(NewAction);
   if (not Assigned(NewAction)) then
      OutOfMemoryError();
   try
      NewAction^.sa_handler := @SigIntHandler;
      NewAction^.sa_flags := SA_ONESHOT;
      {$IFDEF Linux} NewAction^.sa_restorer := nil; {$ENDIF}
      FillByte(NewAction^.sa_mask, SizeOf(NewAction^.sa_mask), 0);
      if (fpSigAction(baseunix.SIGINT, NewAction, nil) <> 0) then
         raise EKernelError.Create(fpGetErrNo);
   finally
      Dispose(NewAction);
   end;
end;

end.