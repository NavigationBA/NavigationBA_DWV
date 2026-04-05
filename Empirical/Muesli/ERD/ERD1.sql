-- Q1 
-- Q1.1 (a) 辅助SQL：
-- 检查是不是 Invoice 和 Sales Order 是一对一关系

SELECT 
    SO.Document_Number        AS Document_Number_SO,
    COUNT(SI.Document_Number) AS Invoice_Count
FROM            Sales_Invoices  AS SI
FULL OUTER JOIN Sales_Orders    AS SO ON SI.Document_Number = SO.Document_Number
GROUP BY SO.Document_Number
-- HAVING COUNT(SI.Document_Number) > 1
;

-- Q1.1 (b) 辅助SQL：
-- 检查 Production Order 和 Production Yield 是一对多关系（一个生产订单可以有多个生产产出记录）
SELECT 
    PO.Document_Number        AS Document_Number_PO,
    COUNT(PY.Document_Number) AS Yield_Count
FROM            Production_Yields AS PY
FULL OUTER JOIN Production_Orders AS PO ON PY.Document_Number = PO.Document_Number
GROUP BY PO.Document_Number
-- HAVING COUNT(PY.Document_Number) > 1
;

-- Q1.2 辅助SQL：
-- 检查 Sales Order Items 中，是不是一个 Item Number 只能对应一个 Material Code
SELECT 
    Document_Number,
    Item_Number,
    COUNT(DISTINCT Material_Code) AS Material_Code_Count
FROM            Sales_Order_Items
GROUP BY Document_Number, Item_Number
-- HAVING COUNT(DISTINCT Material_Code) > 1
;

SELECT * FROM Materials;

-- Q1.3 辅助SQL：
-- 检查有没有 Purchase Order 中的 Document Number 没有对应的 Purchase Order Items 记录
SELECT *
FROM Purchase_Order_Items
WHERE Document_Number NOT IN (SELECT Document_Number FROM Purchase_Orders)
;

-- Q2
-- Q2.1
/*
Weighted average purchase cost of each raw material

- Only include purchases made in the prior 13 weeks (a rolling quarter), excluding the current week.
- Per kg for edible food items.
- Per piece for packaging boxes and bags.
*/

SELECT * FROM Purchase_Order_Items;

SELECT 
    POI.Material_Code,
    SUM(POI.Order_Quantity) AS Total_Quantity,
    SUM(POI.Order_Quantity * POI.Price) / SUM(POI.Order_Quantity) AS Weighted_Average_Cost
FROM Purchase_Order_Items AS POI
JOIN Purchase_Orders      AS PO  ON POI.Document_Number = PO.Document_Number
WHERE PO.Order_Date >= DATEADD(WEEK, -13, DATETRUNC(WEEK, GETDATE()))
AND   PO.Order_Date <  DATETRUNC(WEEK, GETDATE())
GROUP BY POI.Material_Code;


WITH
Purchases_Quarter AS (
    SELECT 
        POI.Material_Code,
        SUM(POI.Order_Quantity) AS Total_Quantity,
        SUM(POI.Order_Quantity * POI.Price) / SUM(POI.Order_Quantity) AS Weighted_Average_Cost
    FROM Purchase_Order_Items AS POI
    JOIN Purchase_Orders      AS PO  ON POI.Document_Number = PO.Document_Number
    WHERE PO.Order_Date >= DATEADD(WEEK, -13, DATETRUNC(WEEK, GETDATE()))
    AND   PO.Order_Date <  DATETRUNC(WEEK, GETDATE())
    GROUP BY POI.Material_Code
)
SELECT 
    M.Material_Code,
    M.Material_Name,
    M.Unit_Size,
    COALESCE(PQ.Total_Quantity, 0) AS Total_Quantity,
    PQ.Weighted_Average_Cost
FROM Materials              AS M
LEFT JOIN Purchases_Quarter AS PQ ON M.Material_Code = PQ.Material_Code
WHERE M.Type_Code = 'ROH'
ORDER BY M.Material_Code
;

-- Q2.2
/*
Year-to-date and month-to-date expenditure for each expense category.
*/
WITH
Account_Expenditure AS (
    SELECT 
        GLA.Account_Number,
        GLA.Account_Group,
        GLA.Account_Name,
        GLP.Posting_Date,
        CASE 
            WHEN GLPE.DR_or_CR = 'DR' THEN GLPE.Amount
            ELSE                           GLPE.Amount * -1
        END AS Amount
    FROM GL_Accounts        AS GLA
    JOIN GL_Posting_Entries AS GLPE ON GLA.Account_Number = GLPE.Account_Number
    JOIN GL_Postings        AS GLP ON GLPE.Document_Number = GLP.Document_Number
    WHERE GLA.Account_Group = 'IS-Expenses' 
),
Account_Expenditure_Year AS (
    SELECT 
        Account_Number,
        Account_Name,
        SUM(Amount) AS Total_Expenditure
    FROM Account_Expenditure
    WHERE Posting_Date >= DATETRUNC(YEAR, GETDATE()) 
    GROUP BY Account_Number, Account_Name
),
Account_Expenditure_Month AS (
    SELECT 
        Account_Number,
        Account_Name,
        SUM(Amount) AS Total_Expenditure
    FROM Account_Expenditure
    WHERE Posting_Date >= DATETRUNC(MONTH, GETDATE())
    GROUP BY Account_Number, Account_Name
)
SELECT 
    GLA.Account_Number,
    GLA.Account_Name,
    COALESCE(AEW.Total_Expenditure, 0) AS Total_Expenditure,
    'Year-to-Date' AS Period
FROM GL_Accounts AS GLA
LEFT JOIN  Account_Expenditure_Year AS AEW ON GLA.Account_Number = AEW.Account_Number
WHERE GLA.Account_Group = 'IS-Expenses'

UNION ALL

SELECT 
    GLA.Account_Number,
    GLA.Account_Name,
    COALESCE(AEM.Total_Expenditure, 0) AS Total_Expenditure,
    'Month-to-Date' AS Period
FROM GL_Accounts AS GLA
LEFT JOIN  Account_Expenditure_Month AS AEM ON GLA.Account_Number = AEM.Account_Number
WHERE GLA.Account_Group = 'IS-Expenses'
ORDER BY Account_Number, Period DESC
;

-- Q2.3
/*
Currently available inventory for each product.
*/

-- According to the background infromation, staff count inventory of each product at the end of each day.
-- So, it is reasonable to assume that at each day and each location, the inventory amounts are recorded for all products. 
-- Therefore, we can find the most recent inventory date for each product at each location.
-- Also, we don't need to left join with the material table, because all the products are recorded in the inventory counts, even the ones with zero quantity.

SELECT
    M.Material_Code,
    M.Material_Name,
    SUM(IC.Closing_Quantity) AS Available_Inventory 
FROM Materials        AS M
JOIN Inventory_Counts AS IC ON M.Material_Code = IC.Material_Code
WHERE Inventory_Date = (SELECT MAX(Inventory_Date) FROM Inventory_Counts)
GROUP BY M.Material_Code, M.Material_Name
HAVING SUM(IC.Closing_Quantity) > 0
ORDER BY M.Material_Code
;


-- Q2.4
/*
Revenue and Units sold for each product, for each week:

- Show the most recent weeks first
- Show whole weeks only, i.e., exclude the current week
- Identify each week with a date (e.g., the first day in the week), NOT a week number (1, 2, 3, ..., 52)
*/

WITH
Sales_Data AS (
    SELECT
        DATETRUNC(WEEK, Delivery_Date) AS Week_Start_Date,
        M.Material_Code,
        M.Material_Name,
        SOI.Quantity,
        SOI.Price
    FROM Materials         AS M
    JOIN Sales_Order_Items AS SOI ON M.Material_Code = SOI.Material_Code
    JOIN Sales_Orders      AS SO  ON SOI.Document_Number = SO.Document_Number
)
SELECT
    Week_Start_Date,
    Material_Code,
    Material_Name,
    SUM(Quantity) AS Units_Sold,
    SUM(Quantity * Price) AS Revenue
FROM Sales_Data
WHERE Week_Start_Date < DATETRUNC(WEEK, GETDATE()) -- Exclude current week
GROUP BY Week_Start_Date, Material_Code, Material_Name
ORDER BY Week_Start_Date DESC, Units_Sold DESC
;

WITH 
Week_Count AS (
    SELECT DATEDIFF(WEEK, (SELECT MIN(Delivery_Date) FROM Sales_Orders), GETDATE()) AS Weeks
),
Week_Numbers AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1
    FROM Week_Numbers
    WHERE n < (SELECT Weeks FROM Week_Count)
),
Week_Dates AS (
    SELECT
        DATEADD(WEEK, -n, DATETRUNC(WEEK, GETDATE())) AS Week_Start_Date
    FROM Week_Numbers
),
Week_Products AS (
    SELECT
        WD.Week_Start_Date,
        M.Material_Code,
        M.Material_Name
    FROM Week_Dates AS WD
    CROSS JOIN Materials AS M
    WHERE M.Material_Code IN (SELECT DISTINCT Material_Code FROM Sales_Order_Items)
),
Sales_Data AS (
    SELECT
        DATETRUNC(WEEK, Delivery_Date) AS Week_Start_Date,
        M.Material_Code,
        M.Material_Name,
        SOI.Quantity,
        SOI.Price
    FROM Materials         AS M
    JOIN Sales_Order_Items AS SOI ON M.Material_Code = SOI.Material_Code
    JOIN Sales_Orders      AS SO  ON SOI.Document_Number = SO.Document_Number
),
Sales_Weekly AS (
    SELECT
        Week_Start_Date,
        Material_Code,
        Material_Name,
        SUM(Quantity) AS Units_Sold,
        SUM(Quantity * Price) AS Revenue
    FROM Sales_Data
    WHERE Week_Start_Date < DATETRUNC(WEEK, GETDATE()) -- Exclude current week
    GROUP BY Week_Start_Date, Material_Code, Material_Name
)
SELECT 
    WD.Week_Start_Date,
    WD.Material_Code,
    WD.Material_Name,
    COALESCE(SW.Units_Sold, 0) AS Units_Sold,
    COALESCE(SW.Revenue, 0) AS Revenue
FROM Week_Products AS WD
LEFT JOIN Sales_Weekly AS SW ON WD.Week_Start_Date = SW.Week_Start_Date AND WD.Material_Code = SW.Material_Code AND WD.Material_Name = SW.Material_Name
ORDER BY WD.Week_Start_Date DESC, SW.Units_Sold DESC
;

-- Q2.5
/*
The remaining, yet to be produced, production schedule.
*/
WITH
Production_Process AS (
    SELECT 
        PO.Document_Number,
        PO.Scheduled_Start,
        PO.Scheduled_End,
        PO.Planned_Quantity,
        CASE 
            WHEN PY.Yield IS NOT NULL THEN PY.Yield
            ELSE                           0
        END AS Produced_Quantity
    FROM      Production_Orders AS PO
    LEFT JOIN Production_Yields AS PY ON PO.Document_Number = PY.Document_Number
),
Production_Process_Total AS (
    SELECT 
        Document_Number,
        Scheduled_Start,
        Scheduled_End,
        Planned_Quantity,
        SUM(Produced_Quantity) AS Total_Produced,
        Planned_Quantity - SUM(Produced_Quantity) AS Remaining_Quantity
    FROM Production_Process
    GROUP BY Document_Number, Scheduled_Start, Scheduled_End, Planned_Quantity
)
SELECT
    Document_Number,
    Scheduled_Start,
    Scheduled_End,
    Planned_Quantity,
    Total_Produced,
    Remaining_Quantity
FROM Production_Process_Total
WHERE Remaining_Quantity > 0 -- Only include production orders that are not yet completed
ORDER BY Scheduled_Start
;

-- Q2.6
/*
Relevant details about currently undelivered raw materials, including the number of days it's been since the items were ordered.
*/
SELECT
    PO.Document_Number,
    M.Material_Code,
    M.Material_Name,
    PO.Order_Date,
    PO.Delivery_Date,
    PO.Vendor,
    POI.Order_Quantity,
    DATEDIFF(DAY, PO.Order_Date, GETDATE()) AS Days_Since_Ordered
FROM Purchase_Orders      AS PO
LEFT JOIN Purchase_Order_Items AS POI ON PO.Document_Number = POI.Document_Number
JOIN Materials            AS M  ON POI.Material_Code = M.Material_Code
WHERE PO.Delivery_Date > GETDATE() OR PO.Delivery_Date IS NULL
ORDER BY PO.Order_Date DESC;

-- Q2.7
/*
The balance of each account as of close of business December 31st, for all balance sheet accounts. 
Include the date of the last recorded transaction prior to, or on, December 31 st for each account.
*/
WITH
BS_Journals1 AS (
    SELECT 
        GLA.Account_Number,
        GLA.Account_Name,
        GLA.Account_Group,
        GLP.Posting_Date,
        GLPE.DR_or_CR,
        GLPE.Amount,
        CASE
            WHEN 
                GLA.Account_Group = 'BS-Assets' 
                AND 
                LOWER(GLA.Account_Name) NOT LIKE '%accumulated depreciation%' 
            THEN 1
            ELSE -1
        END AS Direction
    FROM GL_Accounts        AS GLA
    JOIN GL_Posting_Entries AS GLPE ON GLA.Account_Number = GLPE.Account_Number
    JOIN GL_Postings        AS GLP ON GLPE.Document_Number = GLP.Document_Number
    WHERE GLA.Account_Group LIKE 'BS-%'
),
BS_Journals2 AS (
    SELECT 
        Account_Number,
        Account_Name,
        Account_Group,
        Posting_Date,
        CASE 
            WHEN Direction = 1  AND DR_or_CR = 'DR' THEN Amount
            WHEN Direction = 1  AND DR_or_CR = 'CR' THEN Amount * -1
            WHEN Direction = -1 AND DR_or_CR = 'DR' THEN Amount * -1
            WHEN Direction = -1 AND DR_or_CR = 'CR' THEN Amount
            ELSE 0
        END AS Signed_Amount
    FROM BS_Journals1
),
BS_Balance AS (
    SELECT 
        Account_Number,
        Account_Name,
        Account_Group,
        SUM(Signed_Amount) AS Account_Balance,
        MAX(Posting_Date) AS Last_Transaction_Date
    FROM BS_Journals2
    WHERE Posting_Date <= '2025-12-31'
    GROUP BY Account_Number, Account_Name, Account_Group
)
SELECT 
    GLA.Account_Number,
    GLA.Account_Name,
    GLA.Account_Group,
    COALESCE(BSB.Account_Balance, 0) AS Account_Balance,
    BSB.Last_Transaction_Date
FROM GL_Accounts AS GLA
LEFT JOIN BS_Balance AS BSB ON GLA.Account_Number = BSB.Account_Number
WHERE GLA.Account_Group LIKE 'BS-%'
ORDER BY GLA.Account_Group, GLA.Account_Number
;
