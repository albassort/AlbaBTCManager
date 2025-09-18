-- drop table RpcLog;
CREATE TABLE RpcLog (
    UserRowId Integer references Users (RowId),
    ValidLogin boolean not null default true,
    TimeReceived time NOT NULL DEFAULT (strftime('%s','now')),
    RequestBody json not null
);

-- drop table UserCryptoChange;
CREATE TABLE UserCryptoChange (

    Time time NOT NULL DEFAULT (strftime('%s','now')),
    UserRowId Integer references Users (RowId) not null,

    CoinType text not null,  
    CryptoChange REAL not null,

    WithdrawalRowId Integer references UserDepositEvent (RowId),
    DepositRowId Integer references UserWithdrawalEvent (RowId),
    MiscCause text
);

-- drop table DepositRequest;
CREATE TABLE DepositRequest (
    ReceivingAddress varchar(256) not null,
    CoinType Varchar(12) not null,
    ValidLengthSeconds Integer default 7200,

    PayToUser Integer references Users (RowId),

    DepositAmount REAL not null,

    Finished boolean not null default false,
    Expired boolean not null default false,
    IsActive boolean not null default true,
    -- successful =  (Finished  && !Expired && IsActive)
 
    TimeStarted time NOT NULL DEFAULT (strftime('%s','now')),
    TimeEnded timestamp null,
    Callback string
);

-- drop table DepositEvent;
CREATE TABLE DepositEvent(
    DepositRequest Integer references DepositRequest (RowId) not null,
    AmountReceived REAL not null,
    TimeReceived time NOT NULL DEFAULT (strftime('%s','now'))
);

-- drop table TransactionData;
CREATE TABLE TransactionData (
    Time time NOT NULL DEFAULT (strftime('%s','now')),

    Fee REAL not null,

    OutputTotal REAL not null,
    NumberOfOutputs REAL not null,

    --Json Data
    TransactionRaw json not null,
    Txid varchar(256) not null
);

-- drop table users;
CREATE TABLE Users (
    Username varchar(26) unique not null,
    Password blob not null,
    SaltIv blob not null,
    AccountCreationTime time NOT NULL DEFAULT (strftime('%s','now')),
    IsActive booleanean not null default true
);

insert into users(Username, Password, SaltIv) values ('ADMIN', 'CHANGE', 'ME!');

-- drop table WithdrawalRequest;
create table WithdrawalRequest(
  userRowId int,
  timeReceived time NOT NULL DEFAULT (strftime('%s','now')),
  cryptoType varchar(12) not null,
  cryptoAmount REAL not null,
  withdrawalStrategy varchar(24) not null,
  withdrawalAddress varchar(256) not null,
  timeComplete time,
  isComplete bool default false 
);


create table TransactionWatch(
  TxId text not null,
  BlockHeightCreated int not null,
  ConfTarget int not null,
  CallBack json,
  CoinType text not null,
  Notified bool not null default false,
  NotFound bool not null default false
);


create table LndInvoiceAdd(
  NumSatoshi int not null,
  BtcAmount REAL generated always as (NumSatoshi / 100000000.0) STORED,
  Invoice text not null,
  Rhash text not null,
  TimeCreated time NOT NULL DEFAULT (strftime('%s','now')),
  PubKeyPaid string,
  TimePaid time,
  callback text
);

create table LndInvoicePaid(
  NumSatoshi int not null,
  BtcAmount REAL generated always as (NumSatoshi /100000000.0) STORED,
  Invoice text not null,
  Rhash text not null,
  TimeMade time NOT NULL DEFAULT (strftime('%s','now')),
  TimePaid time,
  PubKeyPaid string,
  PaymentAddr string,
  PubKey string
);

create table LndChannelOpened(
  FundingTxId string primary key not null, 
  OutputIndex int not null,
  LclNumSatoshi int not null,
  LclBtcAmount REAL generated always as (LclBtcAmount /100000000.0) STORED,
  PushNumSatoshi int not null,
  PushBtcAmount REAL generated always as (PushBtcAmount /100000000.0) STORED,
  Pubkey string not null,
  TimeClosed time 
);



create table LndChannelClose(
  ChannelId string primary key not null,
  -- Called channelpoint
  FundingTxId string not null,
  NumSatoshiSent int not null,
  NumBtcSent REAL generated always as (NumBtcSent /100000000.0) STORED,
  NumSatoshiReceived int not null,
  NumBtciReceived REAL generated always as (NumSatoshiReceived /100000000.0) STORED,
  Initialted bool,
  Pubkey string not null,
  CloseType string,
  Closer string,
  ClosedTime time NOT NULL DEFAULT (strftime('%s','now')),
  callback text
);


