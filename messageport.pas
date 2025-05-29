{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit messageport;

{$DEFINE TESTS}

interface

type
   generic TMessagePort<T> = class abstract
   strict private
      FOther: specialize TMessagePort<T>;
      function IsConnected(): Boolean; inline;
   protected
      constructor Create(); virtual;
      class procedure CreateChannel(out A, B);
      property Other: specialize TMessagePort<T> read FOther;
      procedure Send(Message: T);
      procedure HandleMessage(Message: T); virtual; abstract;
      procedure Disconnect(); virtual;
   public
      destructor Destroy(); override;
      property Connected: Boolean read IsConnected;
   end;
   
   generic TCustomMessagePort<T> = class(specialize TMessagePort<T>)
   public
      type
         TMessageCallback = procedure (Port: specialize TCustomMessagePort<T>; Message: T) of object;
         TDisconnectCallback = procedure (Port: specialize TCustomMessagePort<T>) of object;
   private
      FOnMessage: TMessageCallback;
      FOnDisconnect: TDisconnectCallback;
   protected
      procedure HandleMessage(Message: T); override;
      procedure Disconnect(); override;
   public
      property OnMessage: TMessageCallback read FOnMessage write FOnMessage;
      property OnDisconnect: TDisconnectCallback read FOnDisconnect write FOnDisconnect;
   end;

implementation

{$IFDEF TESTS}
uses sysutils;
{$ENDIF}

constructor TMessagePort.Create();
begin
   inherited;
end;

class procedure TMessagePort.CreateChannel(out A, B);
var
   P1: specialize TMessagePort<T> absolute A;
   P2: specialize TMessagePort<T> absolute B;
begin
   P1 := Create();
   P2 := Create();
   P1.FOther := P2;
   P2.FOther := P1;
end;

function TMessagePort.IsConnected(): Boolean;
begin
   Result := Assigned(FOther);
end;

procedure TMessagePort.Send(Message: T);
begin
   Assert(Assigned(FOther));
   FOther.HandleMessage(Message);
end;

procedure TMessagePort.Disconnect();
begin
   FOther := nil;
end;

destructor TMessagePort.Destroy();
begin
   if (Assigned(FOther)) then
   begin
      FOther.Disconnect();
      FOther := nil;
   end;
   inherited;
end;


procedure TCustomMessagePort.HandleMessage(Message: T);
begin
   if (Assigned(FOnMessage)) then
      FOnMessage(Self, Message);
end;

procedure TCustomMessagePort.Disconnect();
begin
   inherited;
   if (Assigned(FOnDisconnect)) then
      FOnDisconnect(Self);
end;


{$IFDEF TESTS}
var
   Log: UTF8String;
   
type
   TMessagePortTest = class
      FID: UTF8String;
      FPort: specialize TCustomMessagePort<Integer>;
      constructor Create(AID: UTF8String; APort: specialize TCustomMessagePort<Integer>);
      destructor Destroy(); override;
      procedure HandleMessage(Port: specialize TCustomMessagePort<Integer>; Message: Integer);
      procedure HandleDisconnect(Port: specialize TCustomMessagePort<Integer>);
      procedure Test();
   end;

constructor TMessagePortTest.Create(AID: UTF8String; APort: specialize TCustomMessagePort<Integer>);
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

procedure TMessagePortTest.HandleMessage(Port: specialize TCustomMessagePort<Integer>; Message: Integer);
begin
   Log := Log + FID + ' RECEIVED ' + IntToStr(Message) + #$0A;
end;

procedure TMessagePortTest.HandleDisconnect(Port: specialize TCustomMessagePort<Integer>);
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
   A, B: specialize TCustomMessagePort<Integer>;
   X, Y: TMessagePortTest;
initialization
   specialize TCustomMessagePort<Integer>.CreateChannel(A, B);
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