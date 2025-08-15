-- drop table RpcLog;
CREATE TABLE RpcLog (
    UserRowId Integer references Users (RowId),
    ValidLogin boolean not null default true,
    TimeRecieved time NOT NULL DEFAULT (strftime('%s','now')),
    RequestBody json not null
);

-- drop table UserCryptoChange;
CREATE TABLE UserCryptoChange (

    Time time NOT NULL DEFAULT (strftime('%s','now')),
    UserRowId Integer references Users (RowId) not null,

    CryptoType text not null,  
    CryptoChange decimal not null,

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

    DepositAmount decimal not null,

    Finished boolean not null default false,
    Expired boolean not null default false,
    IsActive boolean not null default true,
    -- successful =  (Finished  && !Expired && IsActive)
 
    TimeStarted time NOT NULL DEFAULT (strftime('%s','now')),
    TimeEnded timestamp null
);

-- drop table DepositEvent;
CREATE TABLE DepositEvent(
    DepositRequest Integer references DepositRequest (RowId) not null,
    AmounntRecieved decimal not null,
    TimeRecieved time NOT NULL DEFAULT (strftime('%s','now'))
);

-- drop table TransactionData;
CREATE TABLE TransactionData (
    Time time NOT NULL DEFAULT (strftime('%s','now')),

    Fee decimal not null,

    OutputTotal decimal not null,
    NumberOfOutputs decimal not null,

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
  timeRecieved time NOT NULL DEFAULT (strftime('%s','now')),
  cryptoType varchar(12) not null,
  cryptoAmount decimal not null,
  withdrawalStrategy varchar(24) not null,
  withdrawalAddress varchar(256) not null,
  timeComplete time,
  isComplete bool default false 
);


create table TransactionWatch(
  TxId text not null,
  BlockHeightCreated int not null,
  confTargetNotify int not null,
  callBack json,
  CryptoType text not null
)

