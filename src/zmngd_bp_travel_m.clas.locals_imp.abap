CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS earlynumbering_create FOR NUMBERING
       entities FOR CREATE Travel.
    METHODS earlynumbering_cba_Booking FOR NUMBERING
       entities FOR CREATE Travel\_Booking.
    METHODS copyTravel FOR MODIFY
       keys FOR ACTION Travel~copyTravel.
    METHODS acceptTravel FOR MODIFY
       keys FOR ACTION Travel~acceptTravel RESULT result.
    METHODS ReCalcTotalPrice FOR MODIFY
       keys FOR ACTION Travel~ReCalcTotalPrice.
    METHODS rejectTravel FOR MODIFY
       keys FOR ACTION Travel~rejectTravel RESULT result.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Travel RESULT result.
    METHODS validatecustomer FOR VALIDATE ON SAVE
       keys FOR travel~validatecustomer.
    METHODS validateagency FOR VALIDATE ON SAVE
       keys FOR travel~validateagency.
    METHODS validatedates FOR VALIDATE ON SAVE
       keys FOR travel~validatedates.
    METHODS validatestatus FOR VALIDATE ON SAVE
       keys FOR travel~validatestatus.
    METHODS validatecurrencycode FOR VALIDATE ON SAVE
       keys FOR travel~validatecurrencycode.
    METHODS validatebookingfee FOR VALIDATE ON SAVE
       keys FOR travel~validatebookingfee.

ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.

  METHOD earlynumbering_create.

    DATA:
      entity        TYPE STRUCTURE FOR CREATE zmngd_I_Travel_M,
      travel_id_max TYPE /dmo/travel_id.

    " Ensure Travel ID is not set yet (idempotent)- must be checked when BO is draft-enabled
    LOOP AT entities INTO entity WHERE TravelId IS NOT INITIAL.
      APPEND CORRESPONDING #( entity ) TO mapped-travel.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.
    DELETE entities_wo_travelid WHERE TravelId IS NOT INITIAL.

    " Get Numbers
    TRY.
        cl_numberrange_runtime=>number_get(
            EXPORTING
            nr_range_nr = '01'
            object = 'ZMGD_TRV_M'
            quantity = CONV #( lines( entities_wo_travelid ) )
            IMPORTING
            number = DATA(number_range_key)
            returncode = DATA(number_range_return_code)
            returned_quantity = DATA(number_range_returned_quantity)
         ).
      CATCH cx_number_ranges INTO DATA(lx_number_ranges).
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %msg = lx_number_ranges
                        ) TO reported-travel.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                        ) TO failed-travel.
        ENDLOOP.
        EXIT.
    ENDTRY.

    CASE number_range_return_code.
      WHEN '1'.
        " 1 - the returned number is in a critical range (specified under “percentage warning” in the object definition)
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>number_range_depleted
                                   severity = if_abap_behv_message=>severity-warning )
                      ) TO reported-travel.
        ENDLOOP.

      WHEN '2' OR '3'.
        " 2 - the last number of the interval was returned
        " 3 - if fewer numbers are available than requested,  the return code is 3
        LOOP AT entities_wo_travelid INTO entity.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %msg = NEW /dmo/cm_flight_messages(
                                   textid = /dmo/cm_flight_messages=>not_sufficient_numbers
                                   severity = if_abap_behv_message=>severity-warning )
                      ) TO reported-travel.
          APPEND VALUE #( %cid = entity-%cid
                          %key = entity-%key
                          %fail-cause = if_abap_behv=>cause-conflict
                      ) TO failed-travel.
        ENDLOOP.
        EXIT.
    ENDCASE.

    " At this point ALL entities get a number!
    ASSERT number_range_returned_quantity = lines( entities_wo_travelid ).

    travel_id_max = number_range_key - number_range_returned_quantity.

    "Set Travel Id
    LOOP AT entities_wo_travelid INTO entity.
      travel_id_max += 1.
      entity-TravelId = travel_id_max.

      APPEND VALUE #( %cid = entity-%cid
                      %key = entity-%key
                  ) TO mapped-travel.
    ENDLOOP.

  ENDMETHOD.

  METHOD earlynumbering_cba_Booking.

    DATA: max_booking_id TYPE /dmo/booking_id.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel BY \_Booking
    FROM CORRESPONDING #( entities )
    LINK DATA(bookings).

    " Loop over all unique TravelIDs
    LOOP AT entities ASSIGNING FIELD-SYMBOL(<travel>) GROUP BY <travel>-TravelId.
      " Get highest booking_id from existing bookings belonging to travel
      max_booking_id = REDUCE #( INIT max = CONV /dmo/booking_id( '0' )
                                 FOR booking IN bookings USING KEY entity WHERE ( source-TravelId = <travel>-TravelId )
                                 NEXT max = COND /dmo/booking_id( WHEN booking-target-BookingId > max
                                                                  THEN booking-target-BookingId
                                                                  ELSE max )
                               ).
      " Get highest assigned booking_id from incoming entities, eg from internal operations
      max_booking_id = REDUCE #( INIT max = max_booking_id
                                 FOR entity IN entities USING KEY entity WHERE ( TravelId = <travel>-TravelId )
                                 FOR target IN entity-%target
                                 NEXT max = COND /dmo/booking_id( WHEN target-BookingId > max
                                                                  THEN target-BookingId
                                                                  ELSE max )
                               ).

      " Assign new booking-ids if not already assigned
      LOOP AT <travel>-%target ASSIGNING FIELD-SYMBOL(<booking_wo_numbers>).
        APPEND CORRESPONDING #( <booking_wo_numbers> ) TO mapped-booking ASSIGNING FIELD-SYMBOL(<mapped_booking>).
        IF <booking_wo_numbers>-BookingId IS INITIAL.
          max_booking_id += 10.
          <mapped_booking>-BookingId = max_booking_id.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

  METHOD copyTravel.

    DATA:
      travels       TYPE TABLE FOR CREATE zmngd_I_Travel_M\\travel,
      bookings_cba  TYPE TABLE FOR CREATE zmngd_I_Travel_M\\travel\_booking,
      booksuppl_cba TYPE TABLE FOR CREATE zmngd_I_Travel_M\\booking\_booksupplement.

    READ TABLE keys WITH KEY %cid = '' INTO DATA(key_with_inital_cid).
    ASSERT key_with_inital_cid IS INITIAL.

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travel_read_result).

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel BY \_Booking
    ALL FIELDS WITH CORRESPONDING #( travel_read_result )
    RESULT DATA(book_read_result).

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY Booking BY \_BookSupplement
    ALL FIELDS WITH CORRESPONDING #( book_read_result )
    RESULT DATA(booksuppl_read_result).

    LOOP AT keys INTO DATA(key).
      READ TABLE travel_read_result ASSIGNING FIELD-SYMBOL(<travel>) WITH KEY id COMPONENTS %tky = key-%tky.
      IF sy-subrc EQ 0.
        "Fill travel container for creating new travel instance
        APPEND VALUE #( %cid = key-%cid
                        %data = CORRESPONDING #( <travel> EXCEPT TravelId ) )
        TO travels ASSIGNING FIELD-SYMBOL(<new_travel>).

        "Fill %cid_ref of travel as instance identifier for cba booking
        APPEND VALUE #( %cid_ref = key-%cid ) TO bookings_cba ASSIGNING FIELD-SYMBOL(<bookings_cba>).

        <new_travel>-BeginDate = cl_abap_context_info=>get_system_date( ).
        <new_travel>-EndDate = cl_abap_context_info=>get_system_date( ) + 30.
        <new_travel>-OverallStatus = 'O'. "Set to open to allow an editable instance

        LOOP AT book_read_result ASSIGNING FIELD-SYMBOL(<booking>) USING KEY entity WHERE TravelId EQ <travel>-TravelId.
          "Fill booking container for creating booking with cba
          APPEND VALUE #( %cid = key-%cid && <booking>-BookingId
                          %data = CORRESPONDING #( book_read_result[ KEY entity %tky = <booking>-%tky ] EXCEPT TravelId ) )
          TO <bookings_cba>-%target ASSIGNING FIELD-SYMBOL(<new_booking>).

          "Fill %cid_ref of booking as instance identifier for cba booksuppl
          APPEND VALUE #( %cid_ref = key-%cid && <booking>-BookingId ) TO booksuppl_cba ASSIGNING FIELD-SYMBOL(<booksuppl_cba>).

          <new_booking>-BookingStatus = 'N'.

          LOOP AT booksuppl_read_result ASSIGNING FIELD-SYMBOL(<booksuppl>) USING KEY entity WHERE TravelId EQ <travel>-TravelId
          AND BookingId EQ <booking>-BookingId.
            "Fill booksuppl container for creating supplement with cba
            APPEND VALUE #( %cid = key-%cid && <booking>-BookingId && <booksuppl>-BookingSupplementId
                            %data = CORRESPONDING #( <booksuppl> EXCEPT TravelId BookingId ) )
            TO <booksuppl_cba>-%target.
          ENDLOOP.
        ENDLOOP.
      ELSE.
        APPEND CORRESPONDING #( key MAPPING %fail = DEFAULT VALUE #( cause = if_abap_behv=>cause-not_found ) ) TO failed-travel.
      ENDIF.
    ENDLOOP.

    "create new BO instance
    MODIFY ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    CREATE FIELDS ( AgencyId CustomerId BeginDate EndDate BookingFee TotalPrice CurrencyCode OverallStatus Description )
    WITH travels
    CREATE BY \_Booking FIELDS ( BookingId BookingDate CustomerId CarrierId ConnectionId FlightDate FlightPrice CurrencyCode BookingStatus )
    WITH bookings_cba
    ENTITY Booking
    CREATE BY \_BookSupplement FIELDS ( BookingSupplementId SupplementId Price CurrencyCode )
    WITH booksuppl_cba
    MAPPED DATA(mapped_create).

    mapped-travel = mapped_create-travel.

  ENDMETHOD.

  METHOD acceptTravel.

    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    MODIFY ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky OverallStatus = 'A' ) ).

    " Read changed data for action result
    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky = travel-%tky %param = travel ) ).

  ENDMETHOD.

  METHOD rejectTravel.

    " Modify in local mode: BO-related updates that are not relevant for authorization checks
    MODIFY ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    UPDATE FIELDS ( OverallStatus )
    WITH VALUE #( FOR key IN keys ( %tky = key-%tky OverallStatus = 'X' ) ).

    " Read changed data for action result
    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels ( %tky = travel-%tky %param = travel ) ).

  ENDMETHOD.

  METHOD ReCalcTotalPrice.

    TYPES: BEGIN OF ty_amount_per_currencycode,
             amount        TYPE /dmo/total_price,
             currency_code TYPE /dmo/currency_code,
           END OF ty_amount_per_currencycode.

    DATA: amounts_per_currencycode TYPE STANDARD TABLE OF ty_amount_per_currencycode.

    " Read all relevant travel instances.
    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( BookingFee CurrencyCode )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DELETE travels WHERE CurrencyCode IS INITIAL.

    " Read all associated bookings and add them to the total price.
    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel BY \_booking
    FIELDS ( FlightPrice CurrencyCode )
    WITH CORRESPONDING #( travels )
    RESULT DATA(bookings).

    " Read all associated booking supplements and add them to the total price.
    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY booking BY \_booksupplement
    FIELDS ( price currencycode )
    WITH CORRESPONDING #( bookings )
    RESULT DATA(bookingsupplements).

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      " Set the start for the calculation by adding the booking fee.
      amounts_per_currencycode = VALUE #( ( amount        = <travel>-BookingFee
                                            currency_code = <travel>-CurrencyCode ) ).
      LOOP AT bookings INTO DATA(booking) USING KEY id WHERE   TravelId = <travel>-TravelId
                                                       AND     CurrencyCode IS NOT INITIAL.
        COLLECT VALUE ty_amount_per_currencycode( amount        = booking-FlightPrice
                                                  currency_code = booking-CurrencyCode
                                                ) INTO amounts_per_currencycode.
      ENDLOOP.

      LOOP AT bookingsupplements INTO DATA(bookingsupplement) USING KEY id WHERE   TravelId = <travel>-TravelId
                                                                           AND     CurrencyCode IS NOT INITIAL.
        COLLECT VALUE ty_amount_per_currencycode( amount        = bookingsupplement-price
                                                  currency_code = bookingsupplement-CurrencyCode
                                                ) INTO amounts_per_currencycode.
      ENDLOOP.

      DELETE amounts_per_currencycode WHERE currency_code IS INITIAL.
      CLEAR <travel>-TotalPrice.

      LOOP AT amounts_per_currencycode INTO DATA(amount_per_currencycode).
        " If needed do a Currency Conversion
        IF amount_per_currencycode-currency_code = <travel>-CurrencyCode.
          <travel>-TotalPrice += amount_per_currencycode-amount.
        ELSE.
          /dmo/cl_flight_amdp=>convert_currency(
             EXPORTING
               iv_amount                   =  amount_per_currencycode-amount
               iv_currency_code_source     =  amount_per_currencycode-currency_code
               iv_currency_code_target     =  <travel>-CurrencyCode
               iv_exchange_rate_date       =  cl_abap_context_info=>get_system_date( )
             IMPORTING
               ev_amount                   = DATA(total_booking_price_per_curr)
            ).
          <travel>-TotalPrice += total_booking_price_per_curr.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " write back the modified total_price of travels
    MODIFY ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    UPDATE FIELDS ( TotalPrice )
    WITH CORRESPONDING #( travels ).

  ENDMETHOD.


  METHOD get_instance_features.

    READ ENTITIES OF ZMNGD_I_Travel_M IN LOCAL MODE
    ENTITY Travel
    FIELDS ( TravelId OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels)
    FAILED failed.

    result = VALUE #( FOR travel IN travels (
        %tky = travel-%tky
        %features-%action-rejectTravel = COND #( WHEN travel-OverallStatus = 'X'
                                                 THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %features-%action-acceptTravel = COND #( WHEN travel-OverallStatus = 'A'
                                                 THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %assoc-_Booking = COND #( WHEN travel-OverallStatus = 'X'
                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
     ) ).

  ENDMETHOD.

  METHOD validateCustomer.

    " Read relevant travel instance data
    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( CustomerId )
    WITH CORRESPONDING #(  keys )
    RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.
    " Optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = CustomerId EXCEPT * ).

    DELETE customers WHERE customer_id IS INITIAL.

    IF customers IS NOT INITIAL.
      " Check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
        FOR ALL ENTRIES IN @customers
        WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(customers_db).
    ENDIF.

    " Raise msg for non existing and initial customer id
    LOOP AT travels INTO DATA(travel).
      IF travel-CustomerId IS INITIAL OR NOT line_exists( customers_db[ customer_id = travel-CustomerId ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #(  %tky = travel-%tky
                         %msg      = NEW /dmo/cm_flight_messages(
                                         customer_id = travel-CustomerId
                                         textid      = /dmo/cm_flight_messages=>customer_unkown
                                         severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerId = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateAgency.

    " Read relevant travel instance data
    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
     FIELDS ( AgencyId )
     WITH CORRESPONDING #(  keys )
    RESULT DATA(travels).

    DATA agencies TYPE SORTED TABLE OF /dmo/agency WITH UNIQUE KEY agency_id.

    " Optimization of DB select: extract distinct non-initial agency IDs
    agencies = CORRESPONDING #(  travels DISCARDING DUPLICATES MAPPING agency_id = AgencyId EXCEPT * ).
    DELETE agencies WHERE agency_id IS INITIAL.

    IF  agencies IS NOT INITIAL.
      " check if agency ID exist
      SELECT FROM /dmo/agency FIELDS agency_id
        FOR ALL ENTRIES IN @agencies
        WHERE agency_id = @agencies-agency_id
        INTO TABLE @DATA(agencies_db).
    ENDIF.

    " Raise msg for non existing and initial agency id
    LOOP AT travels INTO DATA(travel).
      IF travel-AgencyId IS INITIAL
         OR NOT line_exists( agencies_db[ agency_id = travel-AgencyId ] ).

        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky               = travel-%tky
                        %msg               = NEW /dmo/cm_flight_messages(
                        textid    = /dmo/cm_flight_messages=>agency_unkown
                        agency_id = travel-AgencyId
                        severity  = if_abap_behv_message=>severity-error )
                        %element-AgencyId = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateDates.

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( BeginDate EndDate )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).
      IF travel-EndDate < travel-BeginDate.  "end_date before begin_date
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                   textid     = /dmo/cm_flight_messages=>begin_date_bef_end_date
                                   severity   = if_abap_behv_message=>severity-error
                                   begin_date = travel-BeginDate
                                   end_date   = travel-EndDate
                                   travel_id  = travel-TravelId )
                        %element-BeginDate   = if_abap_behv=>mk-on
                        %element-EndDate     = if_abap_behv=>mk-on
                     ) TO reported-travel.
      ELSEIF travel-BeginDate < cl_abap_context_info=>get_system_date( ).  "begin_date must be in the future
        APPEND VALUE #( %tky        = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky = travel-%tky
                        %msg = NEW /dmo/cm_flight_messages(
                                    textid   = /dmo/cm_flight_messages=>begin_date_on_or_bef_sysdate
                                    severity = if_abap_behv_message=>severity-error )
                        %element-BeginDate  = if_abap_behv=>mk-on
                        %element-EndDate    = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateStatus.

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( OverallStatus )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).
      CASE travel-OverallStatus.
        WHEN 'O'.  " Open
        WHEN 'X'.  " Cancelled
        WHEN 'A'.  " Accepted

        WHEN OTHERS.
          APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

          APPEND VALUE #( %tky                    = travel-%tky
                          %msg                    = NEW /dmo/cm_flight_messages(
                          textid   = /dmo/cm_flight_messages=>status_invalid
                          severity = if_abap_behv_message=>severity-error
                          status   = travel-OverallStatus )
                          %element-OverallStatus = if_abap_behv=>mk-on
                        ) TO reported-travel.
      ENDCASE.

    ENDLOOP.

  ENDMETHOD.

  METHOD validateCurrencyCode.

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( CurrencyCode )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    DATA currencies TYPE SORTED TABLE OF I_Currency WITH UNIQUE KEY currency.

    currencies = CORRESPONDING #(  travels DISCARDING DUPLICATES MAPPING currency = CurrencyCode EXCEPT * ).
    DELETE currencies WHERE currency IS INITIAL.

    IF currencies IS NOT INITIAL.
      SELECT FROM I_Currency FIELDS currency
        FOR ALL ENTRIES IN @currencies
        WHERE currency = @currencies-currency
        INTO TABLE @DATA(currency_db).
    ENDIF.


    LOOP AT travels INTO DATA(travel).
      IF travel-CurrencyCode IS INITIAL.
        " Raise message for empty Currency
        APPEND VALUE #( %tky                   = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky                   = travel-%tky
                        %msg                   = NEW /dmo/cm_flight_messages(
                        textid   = /dmo/cm_flight_messages=>currency_required
                        severity = if_abap_behv_message=>severity-error )
                        %element-CurrencyCode = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ELSEIF NOT line_exists( currency_db[ currency = travel-CurrencyCode ] ).
        " Raise message for not existing Currency
        APPEND VALUE #( %tky                   = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky                   = travel-%tky
                        %msg                   = NEW /dmo/cm_flight_messages(
                        textid        = /dmo/cm_flight_messages=>currency_not_existing
                        severity      = if_abap_behv_message=>severity-error
                        currency_code = travel-CurrencyCode )
                        %element-CurrencyCode = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD validateBookingFee.

    READ ENTITIES OF zmngd_I_Travel_M IN LOCAL MODE
    ENTITY travel
    FIELDS ( BookingFee )
    WITH CORRESPONDING #( keys )
    RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel) WHERE BookingFee < 0.
      " Raise message for booking fee < 0
      APPEND VALUE #( %tky                 = travel-%tky ) TO failed-travel.
      APPEND VALUE #( %tky                 = travel-%tky
                      %msg                 = NEW /dmo/cm_flight_messages(
                      textid   = /dmo/cm_flight_messages=>booking_fee_invalid
                      severity = if_abap_behv_message=>severity-error )
                      %element-BookingFee = if_abap_behv=>mk-on
                    ) TO reported-travel.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.


















