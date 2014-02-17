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
            url: '/GetCFData',
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

    var autofill_custom_fields = function() {
        var cf_data = {};
        jQuery("[class*=CF-]").each(function(){
            cf_data[$(this).attr('id')] = $(this).val();
        });
        update_fields(cf_data);
    };
    jQuery('.autofill_custom_fields').click(function(ev){
        ev.preventDefault();
        autofill_custom_fields();
    });
});
