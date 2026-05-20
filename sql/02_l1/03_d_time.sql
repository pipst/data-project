-- l1.d_time — kalendářní dimenze.
IF OBJECT_ID('l1.d_time', 'U') IS NOT NULL
    DROP TABLE l1.d_time;
GO

CREATE TABLE l1.d_time (
    [date]      DATE         NOT NULL PRIMARY KEY,
    [day]       SMALLINT     NOT NULL,
    day_name    VARCHAR(12)  NOT NULL,
    [month]     SMALLINT     NOT NULL,
    month_name  VARCHAR(12)  NOT NULL,
    [quarter]   SMALLINT     NOT NULL,
    [year]      INT          NOT NULL,
    is_weekend  BIT          NOT NULL
);
GO
