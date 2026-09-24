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

    result = value #( for travel in travels (
        %tky = travel-%tky
        %features-%action-rejectTravel = COND #( WHEN travel-OverallStatus = 'X'
                                                 THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %features-%action-acceptTravel = COND #( WHEN travel-OverallStatus = 'A'
                                                 THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
        %assoc-_Booking = COND #( WHEN travel-OverallStatus = 'X'
                                  THEN if_abap_behv=>fc-o-disabled ELSE if_abap_behv=>fc-o-enabled )
     ) ).

  ENDMETHOD.

ENDCLASS.


















