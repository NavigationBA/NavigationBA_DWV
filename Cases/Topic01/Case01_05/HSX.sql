/*
Q1: 
Total box office earnings to date, for each movie that had new earnings last week. 
You will also need a subquery here - find which movies that had earnings last week (use dynamic date filtering). 
Your outer query can then aggregate the total earnings for each of the movies identified by your subquery.
*/

-- 版本一：一周的开始是周日
WITH
Earnings_Last_Week AS (
    SELECT 
        Release_Id,
        SUM(Gross_Earnings) AS Total_Earnings_Last_Week
    FROM Box_Office_Earnings
    WHERE Earnings_Date <  DATETRUNC(WEEK, GETDATE())
    AND   Earnings_Date >= DATEADD(DAY, -7, DATETRUNC(WEEK, GETDATE()))
    GROUP BY Release_Id
    HAVING SUM(Gross_Earnings) > 0
)
SELECT
    BOR.Release_Id,
    BOR.Name AS Movie_Name,
    SUM(BOE.Gross_Earnings) AS Total_Earnings_To_Date
FROM Box_Office_Earnings AS BOE
JOIN Box_Office_Releases AS BOR ON BOE.Release_Id = BOR.Release_Id
WHERE BOE.Release_Id IN (SELECT Release_Id FROM Earnings_Last_Week)
GROUP BY BOR.Release_Id, BOR.Name
ORDER BY Total_Earnings_To_Date DESC
;


-- 版本二：一周的开始是周一
WITH
Week_Start AS (
    SELECT DISTINCT
        Earnings_Date,
        CASE 
            -- 周一到周六：一周起点为本周一
            WHEN DATEPART(WEEKDAY, Earnings_Date) != 1 THEN DATEADD(DAY,  1, DATETRUNC(WEEK, Earnings_Date))
            -- 周日：一周起点为上周一
            ELSE                                            DATEADD(DAY, -6, DATETRUNC(WEEK, Earnings_Date))
        END AS Week_Start_Date,
        CASE 
            -- 周一到周六：一周起点为本周一
            WHEN DATEPART(WEEKDAY, GETDATE()) != 1 THEN DATEADD(DAY,  1, DATETRUNC(WEEK, GETDATE()))
            -- 周日：一周起点为上周一
            ELSE                                        DATEADD(DAY, -6, DATETRUNC(WEEK, GETDATE()))
        END AS This_Week_Start_Date,
        CASE 
            -- 周一到周六：一周起点为本周一
            WHEN DATEPART(WEEKDAY, DATEADD(DAY, -7, GETDATE())) != 1 THEN DATEADD(DAY,  1, DATETRUNC(WEEK, DATEADD(DAY, -7, GETDATE())))
            -- 周日：一周起点为上周一
            ELSE                                                          DATEADD(DAY, -6, DATETRUNC(WEEK, DATEADD(DAY, -7, GETDATE())))
        END AS Last_Week_Start_Date
    FROM Box_Office_Earnings
),
Week_Start_Filtered AS (
    SELECT 
        Earnings_Date,
        Week_Start_Date,
        This_Week_Start_Date,
        Last_Week_Start_Date
    FROM Week_Start
    WHERE Week_Start_Date = Last_Week_Start_Date
),
Earnings_Last_Week AS (
    SELECT 
        BOE.Release_Id,
        SUM(Gross_Earnings) AS Total_Earnings_Last_Week
    FROM Box_Office_Earnings AS BOE
    JOIN Week_Start_Filtered AS WSF ON BOE.Earnings_Date = WSF.Earnings_Date
    GROUP BY BOE.Release_Id
    HAVING SUM(Gross_Earnings) > 0
)
SELECT
    BOR.Release_Id,
    BOR.Name AS Movie_Name,
    SUM(BOE.Gross_Earnings) AS Total_Earnings_To_Date
FROM Box_Office_Earnings AS BOE
JOIN Box_Office_Releases AS BOR ON BOE.Release_Id = BOR.Release_Id
WHERE BOE.Release_Id IN (SELECT Release_Id FROM Earnings_Last_Week)
GROUP BY BOR.Release_Id, BOR.Name
ORDER BY Total_Earnings_To_Date DESC
;

/*
Q2:
Current price for each securities that can still actively be traded - show highest priced securities first. 
You will need a subqueries or two here - remember it's easier to use CTEs to develop, test, and layer subqueries. 
Build and test your logic piece by piece, step by step.
*/
WITH
Security_Latest_Date AS (
    SELECT 
        Security_Symbol, 
        MAX(Price_Date) AS Latest_Price_Date
    FROM Security_Prices
    WHERE Security_Symbol IN (SELECT Security_Symbol FROM Securities WHERE Status = 'Active')
    GROUP BY Security_Symbol
)
SELECT 
    SP.Security_Symbol,
    S.Name,
    SLD.Latest_Price_Date,
    SP.Closing_Price
FROM Security_Prices      AS SP
JOIN Securities           AS S   ON SP.Security_Symbol = S.Security_Symbol
JOIN Security_Latest_Date AS SLD ON SP.Security_Symbol = SLD.Security_Symbol AND SP.Price_Date = SLD.Latest_Price_Date
;

/*
Q3:
For each trader and each security, the number of securities currently held, and the date and time of the last trade made. 
Use conditional aggregation to make this easier. 
Make sure you investigate the way the data is recorded, rather than making a (wrong) assumption. 
Note that in the stock trading world, Buy and Short open or extend holdings, whereas Sell, Cover and Delist close out holdings.
*/

WITH
Trade_Summary AS (
    SELECT
        User_Name,
        Security_Symbol,
        CASE 
            WHEN Action IN ('Buy', 'Short')            THEN Quantity
            WHEN Action IN ('Sell', 'Cover', 'Delist') THEN Quantity * -1
            ELSE 0
        END AS Quantity_Signed,
        Trade_Date_Time
    FROM Trades
)
SELECT
    T.User_Name,
    A.Trader_Name,
    T.Security_Symbol,
    S.Name AS Security_Name,
    S.Type AS Security_Type,
    SUM(T.Quantity_Signed) AS Currently_Held,
    MAX(T.Trade_Date_Time) AS Last_Trade_Date_Time
FROM Trade_Summary AS T
JOIN Accounts AS A ON T.User_Name = A.User_Name
JOIN Securities AS S ON T.Security_Symbol = S.Security_Symbol
GROUP BY T.User_Name, A.Trader_Name, T.Security_Symbol, S.Name, S.Type
HAVING SUM(T.Quantity_Signed) > 0
ORDER BY A.Trader_Name, Last_Trade_Date_Time DESC
;