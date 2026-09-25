CLASS lhc_booking DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS earlynumbering_cba_Booksupplem FOR NUMBERING
       entities FOR CREATE Booking\_Booksupplement.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Booking RESULT result.
    METHODS validatestatus FOR VALIDATE ON SAVE
       keys FOR booking~validatestatus.
    METHODS validatecustomer FOR VALIDATE ON SAVE
       keys FOR booking~validatecustomer.
    METHODS validateconnection FOR VALIDATE ON SAVE
       keys FOR booking~validateconnection.
    METHODS validatecurrencycode FOR VALIDATE ON SAVE
       keys FOR booking~validatecurrencycode.
    METHODS validateflightprice FOR VALIDATE ON SAVE
      keys FOR booking~validateflightprice.

ENDCLASS.

CLASS lhc_booking IMPLEMENTATION.

  METHOD earlynumbering_cba_Booksupplem.

    DATA: max_booking_suppl_id TYPE /dmo/booking_supplement_id .

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking BY \_BookSupplement
    FROM CORRESPONDING #( entities )
    LINK DATA(booking_supplements).

    " Loop over all unique tky (TravelID + BookingID)
    LOOP AT entities ASSIGNING FIELD-SYMBOL(<booking>) GROUP BY <booking>-%tky.
      " Get highest bookingsupplement_id from bookings belonging to booking
      max_booking_suppl_id = REDUCE #( INIT max = CONV /dmo/booking_supplement_id( '0' )
                                       FOR  booksuppl IN booking_supplements USING KEY entity
                                                                             WHERE ( source-TravelId  = <booking>-TravelId
                                                                                     AND source-BookingId = <booking>-BookingId )
                                       NEXT max = COND /dmo/booking_supplement_id( WHEN booksuppl-target-BookingSupplementId > max
                                                                          THEN booksuppl-target-BookingSupplementId
                                                                          ELSE max )
                                     ).
      " Get highest assigned bookingsupplement_id from incoming entities
      max_booking_suppl_id = REDUCE #( INIT max = max_booking_suppl_id
                                       FOR  entity IN entities USING KEY entity WHERE ( TravelId  = <booking>-TravelId
                                                                                        AND BookingId = <booking>-BookingId )
                                       FOR  target IN entity-%target
                                       NEXT max = COND /dmo/booking_supplement_id( WHEN   target-BookingSupplementId > max
                                                                                   THEN target-BookingSupplementId
                                                                                   ELSE max )
                                     ).

      " Assign new booking_supplement-ids
      LOOP AT <booking>-%target ASSIGNING FIELD-SYMBOL(<booksuppl_wo_numbers>).
        APPEND CORRESPONDING #( <booksuppl_wo_numbers> ) TO mapped-booksuppl ASSIGNING FIELD-SYMBOL(<mapped_booksuppl>).
        IF <booksuppl_wo_numbers>-BookingSupplementId IS INITIAL.
          max_booking_suppl_id += 1 .
          <mapped_booksuppl>-BookingSupplementId = max_booking_suppl_id .
        ENDIF.
      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.

  METHOD get_instance_features.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking
    FIELDS ( BookingId BookingStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings)
    FAILED failed.

    result = VALUE #( FOR booking IN bookings (
        %tky = booking-%tky
        %assoc-_BookSupplement = COND #( WHEN booking-BookingStatus = 'B'
                                         THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
     ) ).

  ENDMETHOD.

  METHOD validateStatus.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY booking
    FIELDS ( BookingStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

    LOOP AT bookings INTO DATA(booking).
      CASE booking-BookingStatus.
        WHEN 'N'.  " New
        WHEN 'X'.  " Canceled
        WHEN 'B'.  " Booked

        WHEN OTHERS.
          APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.

          APPEND VALUE #( %tky = booking-%tky
                          %msg = NEW /dmo/cm_flight_messages(
                                     textid = /dmo/cm_flight_messages=>status_invalid
                                     status = booking-BookingStatus
                                     severity = if_abap_behv_message=>severity-error )
                          %element-BookingStatus = if_abap_behv=>mk-on
                          %path = VALUE #(  travel-travelid    = booking-travelid )
                        ) TO reported-booking.
      ENDCASE.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateCustomer.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking
    FIELDS ( CustomerId )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking BY \_Travel
    FROM CORRESPONDING #( bookings )
    LINK DATA(travel_booking_links).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    " Optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( bookings DISCARDING DUPLICATES MAPPING customer_id = CustomerId EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.

    IF  customers IS NOT INITIAL.
      " Check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
                                FOR ALL ENTRIES IN @customers
                                WHERE customer_id = @customers-customer_id
      INTO TABLE @DATA(valid_customers).
    ENDIF.

    " Raise message for non existing and initial customer id
    LOOP AT bookings INTO DATA(booking).
      IF booking-CustomerId IS  INITIAL.

        APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = booking-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>enter_customer_id
                                   severity = if_abap_behv_message=>severity-error )
                        %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = booking-%tky ]-target-%tky )
                        %element-CustomerId = if_abap_behv=>mk-on
                       ) TO reported-booking.

      ELSEIF booking-CustomerId IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = booking-CustomerId ] ).

        APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = booking-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>customer_unkown
                                   customer_id = booking-CustomerId
                                   severity = if_abap_behv_message=>severity-error )
                        %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = booking-%tky ]-target-%tky )
                        %element-CustomerId = if_abap_behv=>mk-on
                       ) TO reported-booking.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateConnection.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking
    FIELDS ( BookingId CarrierId ConnectionId FlightDate )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking BY \_Travel
    FROM CORRESPONDING #( bookings )
    LINK DATA(travel_booking_links).

    LOOP AT bookings ASSIGNING FIELD-SYMBOL(<booking>).
      " Raise message for non existing airline ID
      IF <booking>-CarrierId IS INITIAL.

        APPEND VALUE #( %tky = <booking>-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = <booking>-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>enter_airline_id
                                   severity = if_abap_behv_message=>severity-error )
                        %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = <booking>-%tky ]-target-%tky )
                        %element-CarrierId = if_abap_behv=>mk-on
                       ) TO reported-booking.
      ENDIF.
      " Raise message for non existing connection ID
      IF <booking>-ConnectionId IS INITIAL.

        APPEND VALUE #( %tky = <booking>-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = <booking>-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>enter_connection_id
                                   severity = if_abap_behv_message=>severity-error )
                        %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = <booking>-%tky ]-target-%tky )
                        %element-ConnectionId = if_abap_behv=>mk-on
                       ) TO reported-booking.
      ENDIF.
      " Raise message for non existing flight date
      IF <booking>-FlightDate IS INITIAL.

        APPEND VALUE #( %tky = <booking>-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = <booking>-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>enter_flight_date
                                   severity = if_abap_behv_message=>severity-error )
                        %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = <booking>-%tky ]-target-%tky )
                        %element-FlightDate = if_abap_behv=>mk-on
                       ) TO reported-booking.
      ENDIF.
      " check if flight connection exists
      IF <booking>-CarrierId IS NOT INITIAL AND
         <booking>-ConnectionId IS NOT INITIAL AND
         <booking>-FlightDate IS NOT INITIAL.

        SELECT SINGLE Carrier_ID, Connection_ID, Flight_Date   FROM /dmo/flight  WHERE  carrier_id    = @<booking>-CarrierId
                                                               AND  connection_id = @<booking>-ConnectionId
                                                               AND  flight_date   = @<booking>-FlightDate
                                                               INTO  @DATA(flight).

        IF sy-subrc <> 0.

          APPEND VALUE #( %tky = <booking>-%tky ) TO failed-booking.
          APPEND VALUE #( %tky = <booking>-%tky
                          %msg = NEW /dmo/cm_flight_messages(
                                     textid      = /dmo/cm_flight_messages=>no_flight_exists
                                     carrier_id  = <booking>-CarrierId
                                     flight_date = <booking>-FlightDate
                                     severity    = if_abap_behv_message=>severity-error )
                          %path = VALUE #( travel-%tky = travel_booking_links[ KEY id  source-%tky = <booking>-%tky ]-target-%tky )
                          %element-FlightDate   = if_abap_behv=>mk-on
                          %element-CarrierId    = if_abap_behv=>mk-on
                          %element-ConnectionId = if_abap_behv=>mk-on
                        ) TO reported-booking.

        ENDIF.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validateCurrencyCode.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY booking
    FIELDS ( CurrencyCode )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

    DATA: currencies TYPE SORTED TABLE OF I_Currency WITH UNIQUE KEY currency.

    currencies = CORRESPONDING #( bookings DISCARDING DUPLICATES MAPPING currency = CurrencyCode EXCEPT * ).
    DELETE currencies WHERE currency IS INITIAL.

    IF currencies IS NOT INITIAL.
      SELECT FROM I_Currency FIELDS currency
        FOR ALL ENTRIES IN @currencies
        WHERE currency = @currencies-currency
        INTO TABLE @DATA(currency_db).
    ENDIF.


    LOOP AT bookings INTO DATA(booking).
      IF booking-CurrencyCode IS INITIAL.
        " Raise message for empty Currency
        APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = booking-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid    = /dmo/cm_flight_messages=>currency_required
                                   severity  = if_abap_behv_message=>severity-error )
                        %element-CurrencyCode = if_abap_behv=>mk-on
                        %path = VALUE #(  travel-travelid    = booking-travelid )
                      ) TO reported-booking.
      ELSEIF NOT line_exists( currency_db[ currency = booking-CurrencyCode ] ).
        " Raise message for not existing Currency
        APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.
        APPEND VALUE #( %tky = booking-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid    = /dmo/cm_flight_messages=>currency_not_existing
                                   severity  = if_abap_behv_message=>severity-error
                                   currency_code = booking-CurrencyCode )
                        %path = VALUE #(  travel-travelid    = booking-travelid )
                        %element-currencycode = if_abap_behv=>mk-on
                      ) TO reported-booking.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateFlightPrice.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY booking
    FIELDS ( FlightPrice )
    WITH CORRESPONDING #( keys )
    RESULT DATA(bookings).

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Booking BY \_Travel
    FROM CORRESPONDING #( bookings )
    LINK DATA(travel_booking_links).

    LOOP AT bookings INTO DATA(booking) WHERE FlightPrice < 0.
      " Raise message for flight price < 0
      APPEND VALUE #( %tky = booking-%tky ) TO failed-booking.
      APPEND VALUE #( %tky = booking-%tky
                      %msg = NEW /dmo/cm_flight_messages(
                                 textid      = /dmo/cm_flight_messages=>flight_price_invalid
                                 severity    = if_abap_behv_message=>severity-error )
                      %element-FlightPrice = if_abap_behv=>mk-on
                      %path = VALUE #( travel-%tky = travel_booking_links[ KEY id source-%tky = booking-%tky ]-target-%tky )
                    ) TO reported-booking.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.



