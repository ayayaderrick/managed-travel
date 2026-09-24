CLASS lhc_booking DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS earlynumbering_cba_Booksupplem FOR NUMBERING
       entities FOR CREATE Booking\_Booksupplement.
    METHODS get_instance_features FOR INSTANCE FEATURES
      keys REQUEST requested_features FOR Booking RESULT result.

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

ENDCLASS.



