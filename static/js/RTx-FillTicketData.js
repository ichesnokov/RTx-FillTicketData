jQuery(function($) {

    function jq(myid) {
        return "#" + myid.replace( /(:|\.|\[|\])/g, "\\$1" );
    }

    var fill_value = function(key, val) {

        // Search subject by name
        if (key == 'Subject') {
            $("input[name='Subject']").each(function() {
                $(this).val(val);
            });
            return;
        }

        // Ticket body is a CKEditor instance
        if (key == 'Body') {
            CKEDITOR.instances.Content.setData(val);
            return;
        }

        // Search other elements (custom fields) by id
        var element = $(jq(key));
        if (element) {
            $(element).val(val);
        } else {
            alert("No element with id: " + key);
        }
    }

    var update_fields = function(cf_data) {
        $.ajax({
            url: '/Helpers/GetTicketData',
            data: cf_data,
            dataType: 'json',
            success: function(data) {
                $.each(data, fill_value);
            },
            error: function(jqXHR, textStatus) {
                alert('Error: ' + textStatus);
            },
        });
    };

    $('.autofill_custom_fields').click(function(ev){
        ev.preventDefault();

        var cf_data = {};

        // Pass custom fields that are currently on page
        $("[class*=CF-]").each(function(){
            // magic value indicating that the field exists on page
            cf_data[$(this).attr('id')] = '__exists__';
        });

        // Store key field value
        var key_field = $(this).parent().prev().children().first().next();
        cf_data[ $(key_field).attr('id') ] = $(key_field).val();

        update_fields(cf_data);
    });
});
