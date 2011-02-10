$(function() {

    function render(part) {
        with(part) {
            return [
                '<div>',
                    '<h1>', title, '</h1>',
                    '<dl>',
                       '<dt>Bron</dt><dd>',source,'</dd>',
                       '<dt>Publicatie</dt><dd>',pubdate,'</dd>',
                       '<dt>nummer</dt><dd>',pubid,'</dd>',
                       '<dt>bladzijde</dt><dd>',pages,'</dd>',
                       '<dt>beeld</dt><dd><a href="',pdf_href,'">PDF</a></dd>',
                       '<dt>Dossiernummer</dt><dd>',docid,'</dd>',
                       '<dt>Inwerkingtreding</dt><dd>',effective,'</dd>',
                    '</dl>',
                '</div>',
            ].join('');
        }
    }

    $("input[type=submit]").bind('click', function(e) {
        e.preventDefault();

        $.ajax({
            url: "/api/list.json", 
            data: { date: $('input[name=date]').val() },
            dataType: 'json',
            success: function(json) {
                var h = [];
                for (var key in json) { h.push(render(json[key])); }
                $("#result").html(h.join(''));
            }
        });

        return false;
    });
});
