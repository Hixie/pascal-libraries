{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit messageport;

{$DEFINE TESTS}

interface

type
   generic TMessagePort<T> = class sealed
   public
      type
         TMessagePortMessageCallback = procedure (Port: specialize TMessagePort<T>; Message: T) of object;
         TMessagePortDisconnectCallback = procedure (Port: specialize TMessagePort<T>) of object;
   protected
      FOther: specialize TMessagePort<T>;
      FMessageCallback: TMessagePortMessageCallback;
      FDisconnectCallback: TMessagePortDisconnectCallback;
   public
      procedure Send(Message: T);
      destructor Destroy(); override;
      property OnMessage: TMessagePortMessageCallback read FMessageCallback write FMessageCallback;
      property OnDisconnect: TMessagePortDisconnectCallback read FDisconnectCallback write FDisconnectCallback;
   end;

generic procedure CreateChannel<T>(out A, B: specialize TMessagePort<T>);
   
implementation

{$IFDEF TESTS}
uses sysutils;
{$ENDIF}

generic procedure CreateChannel<T>(out A, B: specialize TMessagePort<T>);
begin
   A := specialize TMessagePort<T>.Create();
   B := specialize TMessagePort<T>.Create();
   A.FOther := B;
   B.FOther := A;
end;

procedure TMessagePort.Send(Message: T);
begin
   Assert(Assigned(FOther));
   if (Assigned(FOther.FMessageCallback)) then
      FOther.FMessageCallback(FOther, Message);
end;

destructor TMessagePort.Destroy();
begin
   if (Assigned(FOther)) then
   begin
      FOther.FOther := nil;
      if (Assigned(FOther.FDisconnectCallback)) then
         FOther.FDisconnectCallback(FOther);
   end;
   inherited;
end;


{$IFDEF TESTS}
var
   Log: UTF8String;
   
type
   TMessagePortTest = class
      FID: UTF8String;
      FPort: specialize TMessagePort<Integer>;
      constructor Create(AID: UTF8String; APort: specialize TMessagePort<Integer>);
      destructor Destroy(); override;
      procedure HandleMessage(Port: specialize TMessagePort<Integer>; Message: Integer);
      procedure HandleDisconnect(Port: specialize TMessagePort<Integer>);
      procedure Test();
   end;

constructor TMessagePortTest.Create(AID: UTF8String; APort: specialize TMessagePort<Integer>);
begin
   inherited Create();
   FID := AID;
   FPort := APort;
   FPort.OnMessage := @HandleMessage;
   FPort.OnDisconnect := @HandleDisconnect;
end;

destructor TMessagePortTest.Destroy();
begin
   FPort.Free();
   inherited;
end;

procedure TMessagePortTest.HandleMessage(Port: specialize TMessagePort<Integer>; Message: Integer);
begin
   Log := Log + FID + ' RECEIVED ' + IntToStr(Message) + #$0A;
end;

procedure TMessagePortTest.HandleDisconnect(Port: specialize TMessagePort<Integer>);
begin
   Log := Log + FID + ' LOST PARTNER' + #$0A;
   FreeAndNil(FPort);
end;

procedure TMessagePortTest.Test();
begin
   if (Assigned(FPort)) then
      FPort.Send(123);
end;

var
   A, B: specialize TMessagePort<Integer>;
   X, Y: TMessagePortTest;
initialization
   specialize CreateChannel<Integer>(A, B);
   X := TMessagePortTest.Create('X', A);
   Y := TMessagePortTest.Create('Y', B);
   X.Test();
   Y.Test();
   FreeAndNil(X);
   Y.Test();
   FreeAndNil(Y);
   Assert(Log = 'Y RECEIVED 123' + #$0A + 'X RECEIVED 123' + #$0A + 'Y LOST PARTNER' + #$0A);
{$ENDIF}
end.