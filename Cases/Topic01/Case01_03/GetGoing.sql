/*
1. The address of each of the pod locations, and the number of parking spaces in each.
*/
SELECT
    Address,
    Spaces
FROM Locations
ORDER BY Address;

/*
2. The make, model, year, and registration of all unsold vehicles with at least 40,000 km on the odometer.
*/
SELECT
    Make,
    Model,
    DATEPART(YEAR, Purchase_Date) AS Year,
    Registration,
    Odometer
FROM Vehicles
WHERE Sold_Date IS NULL  -- unsold vehicles
AND Odometer >= 40000
ORDER BY Make, Model, Registration;

/*
3. A list of all vehicle make and models that GetGoing has ever owned, along with the number of vehicles of each make and model currently owned.
*/

SELECT 
    Make,
    Model,
    COUNT(*) AS Total_Owned_Count
FROM Vehicles 
WHERE Sold_Date IS NULL  -- currently owned vehicles
GROUP BY Make, Model
ORDER BY Make, Model;

/*
4. The locations that have had the most rentals this month.
*/

SELECT
    L.Location_Id,
    L.Address,
    COUNT(*) AS Rental_Count
FROM Rentals   AS R
JOIN Vehicles  AS V ON R.VIN = V.VIN
JOIN Locations AS L ON V.Location_ID = L.Location_ID
-- WHERE DATEPART(MONTH, Rental_DateTime) = DATEPART(MONTH, GETDATE())  -- rentals in the current month
-- AND   DATEPART(YEAR, Rental_DateTime)  = DATEPART(YEAR, GETDATE())   -- rentals in the current year
-- WHERE FORMAT(Rental_DateTime, 'yyyy-MM') = FORMAT(GETDATE(), 'yyyy-MM')  -- rentals in the current month, alternative way
WHERE Rental_DateTime >= DATETRUNC(MONTH, GETDATE())  -- rentals in the current month, alternative way
GROUP BY L.Location_Id, L.Address
ORDER BY Rental_Count DESC;

/*
5. The most and least popular days of the week that rentals are made.
*/

SELECT
    DATENAME(WEEKDAY, Rental_DateTime) AS DayOfWeek,
    COUNT(*) AS Rental_Count
FROM Rentals
GROUP BY DATENAME(WEEKDAY, Rental_DateTime)
ORDER BY Rental_Count DESC;


/* 
6. The name and join date of the most recent subscribers, who have not rented a car yet
*/

SELECT 
    Name, 
    Join_Date
FROM Subscribers
WHERE Licence_Nbr NOT IN (SELECT DISTINCT Licence_Nbr FROM Rentals)
ORDER BY Join_Date DESC;

SELECT 
    Name, 
    Join_Date
FROM      Subscribers AS S
LEFT JOIN Rentals     AS R ON S.Licence_Nbr = R.Licence_Nbr
WHERE R.Licence_Nbr IS NULL
ORDER BY Join_Date DESC;

/*
7. Relevant car and subscriber details for all cars currently out for rent.
(Note that this is a small data set, and it's quite likely that your query returns no data when there are no cars out for rent)
*/
SELECT 
    V.Make,
    V.Model,
    S.Name AS Subscriber_Name,
    S.Licence_Nbr,
    R.Rental_DateTime
FROM Rentals     AS R
JOIN Vehicles    AS V ON R.VIN = V.VIN
JOIN Subscribers AS S ON R.Licence_Nbr = S.Licence_Nbr
WHERE R.Duration IS NULL  -- cars currently out for rent
ORDER BY R.Rental_DateTime DESC;

/*
8. The list of pod locations (address), and number of vehicles currently available at each location.
*/
WITH
Vehicle_Available AS (
    SELECT 
        L.Location_Id,
        L.Address,
        V.VIN
    FROM Locations AS L
    JOIN Vehicles  AS V ON L.Location_Id = V.Location_Id
    WHERE V.VIN NOT IN (
        SELECT DISTINCT 
            VIN 
        FROM Rentals
        WHERE Duration IS NULL
        )
)
SELECT 
    Location_Id,
    Address,
    COUNT(*) AS Num_Available_Car
FROM Vehicle_Available
GROUP BY Location_Id, Address
ORDER BY Num_Available_Car DESC;