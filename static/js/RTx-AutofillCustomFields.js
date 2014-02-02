jQuery(function($) {
    var update_field_value = function(field) {
        var ids = $(field).attr('class').match(/(\d+)/);
        var field_id = ids[0];
        if (field_id) {
            //jQuery.ajax('/Elements/AutoFillCustomFields', {
            //    data: { key_field_id: field_id },
            //    dataType: 'json',
            //    success: function(data) {
            //        $(field).val(data.value);
            //    },
            //});
            $(field).val('id=' + field_id);
        }
    };
    var autofill_custom_fields = function() {
        var custom_fields = jQuery("[class*=CF-]").each(function(){
            update_field_value(this);
        });
    };
    jQuery('#autofill_custom_fields').click(function(ev){
        ev.preventDefault();
        autofill_custom_fields();
    });
});
