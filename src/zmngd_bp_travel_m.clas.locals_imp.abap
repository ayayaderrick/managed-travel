CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS earlynumbering_create FOR NUMBERING
       entities FOR CREATE Travel.
    METHODS earlynumbering_cba_Booking FOR NUMBERING
       entities FOR CREATE Travel\_Booking.

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

ENDCLASS.


















