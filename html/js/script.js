$(function() {

    /* Proof of Concept code  **************************************************************************************************/

    // layout + initialise ----------------------------------------------------------------------------------------------------
    
    $('body').layout({
        north: {
            resizable: false,
            closable: false,
            spacing_open: 0,
        }
    });

    $('div.ui-layout-container').layout({
        north: {
            size: 250
        }
    });


    if(supports_localstorage()) {
        // keeps bookmarks around
    } else {
        // alert('no localstorage support, upgrade your browser');
    }


    // helper functions -------------------------------------------------------------------------------------------------------
    function supports_localstorage() {
        try {
            return 'localStorage' in window && window['localStorage'] !== null;
        } catch(e) { return false; }
    }

    function render(part,q) {
        if(q) { part.title = part.title.replace(q,'<em class="hl">'+q+'</em>'); }

        return [
            '<tr class="entry" rel="',part.docuid,'">',
                '<td>', part.title, '</td>',
                /*
                '<td style="display:none">',
                '<dl>',
                   '<dt>Link</dt><dd><a href="/doc/show.html?id=',part.docuid,'">',part.docuid,'</a></dd>',
                   '<dt>Bron</dt><dd>',part.source,'</dd>',
                   '<dt>Publicatie</dt><dd>',part.pubdate,'</dd>',
                   '<dt>nummer</dt><dd>',part.pubid,'</dd>',
                   '<dt>bladzijde</dt><dd>',part.pages,'</dd>',
                   '<dt>beeld</dt><dd><a href="http://www.ejustice.just.fgov.be',part.pdf_href,'">PDF</a></dd>',
                   '<dt>Dossiernummer</dt><dd>',part.docuid,'</dd>',
                   '<dt>Inwerkingtreding</dt><dd>',part.effective,'</dd>',
                '</dl>',
                '</td>', */
                '<td class="doc" style="display:none">',part.pretty,'</td>',
            '</tr>',
        ].join(''); 
    }

    function submit() {
        var query = $('input[name=q]').val();
        $('img.spinner').show();
        $.ajax({
            url: "/api/list.json", 
            data: { q: query },
            dataType: 'json',
            success: function(json) {
                var h = [];
                for (var key in json) { h.push(render(json[key],query)); }
                $("#result").html(h.join(''));
                $('img.spinner').hide();
            },
            error: function() {
                alert('unable to fetch data');
                $('img.spinner').hide();
            }
        });
    }

    // triggers ----------------------------------------------------------------------------------------------------------------
    $("#result tr.entry").live('click',function(e) {
        // console.log('fooooo %o',$(this).attr('rel'));
        var docuid = $(this).attr('rel');
        var query = $('input[name=q]').val();
        $('img.spinner').show();
        $.ajax({
            url: "/doc/show.html",
            data: { id: docuid },
            dataType: 'html',
            success: function(h) {
                if(query) { h = h.replace(query,'<em class="hl">'+query+'</em>'); }
                $(".mainview").empty().html(h);
                $('img.spinner').hide();
            },
            error: function() {
                $('img.spinner').hide();
            }
        });
    });

    $("ul.panellist ul.historylist li").live('click', function(e) {
        $('input[name=q]').val($(this).text().trim());
        submit();
    });

    $("input[type=submit]").bind('click', function(e) {
        e.preventDefault();
        submit();
        var query = $('input[name=q]').val();
        $('ul.panellist ul.historylist').append(['<li>',query,'</li>'].join(''));
        return false;
    });

    $("form").bind("submit",function(e) {
        e.preventDefault();
        submit();
        var query = $('input[name=q]').val();
        $('ul.panellist ul.historylist').append(['<li>',query,'</li>'].join(''));
        return false;
    });
});
