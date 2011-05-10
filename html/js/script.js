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

    window.spincount = 0; // internal spincount locker

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

    var urlQuerySearch = window.location.toString().match(/\/s\/([^\/]*)/);
    var urlQueryDocUID = window.location.toString().match(/\/d\/([\w\d\-\/]+)/);

    if(urlQuerySearch) { $('input[name=q]').val(urlQuerySearch[1]); submit(); }
    if(urlQueryDocUID) { show(urlQueryDocUID[1]); }
                

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
        $('img.spinner').show(); window.spincount++;
        $.ajax({
            url: "/api/list.json", 
            data: { q: query },
            dataType: 'json',
            success: function(json) {
                var h = [];
                for (var key in json) { h.push(render(json[key],query)); }
                $("#result").html(h.join(''));
                if(urlQueryDocUID) { 
                    var docuid = urlQueryDocUID[1];
                    $("#result tr.selected").removeClass('selected');
                    console.log('docuid %o el %o', docuid, $("tr.entry[rel='"+docuid+"']"));
                    $("#result tr.entry[rel='"+docuid+"']").addClass('selected');
                }
                if(--window.spincount == 0) { $('img.spinner').hide(); }
            },
            error: function() {
                alert('unable to fetch data');
                if(--window.spincount == 0) { $('img.spinner').hide(); }
            }
        });
    }

    function show(docuid) {
        var query = $('input[name=q]').val();
        $('img.spinner').show(); window.spincount++;
        $.ajax({
            url: "/doc/show.html",
            data: { id: docuid },
            dataType: 'html',
            success: function(h) {
                if(query) { h = h.replace(query,'<em class="hl">'+query+'</em>'); }
                $(".mainview").empty().html(h);
                $("#result tr.selected").removeClass('selected');
                $("#result tr.entry[rel='"+docuid+"']").addClass('selected');
                window.history.pushState({},'BeLawsHub', '/s/' + query + '/d/' + docuid);
                if(--window.spincount == 0) { $('img.spinner').hide(); }
            },
            error: function() {
                if(--window.spincount == 0) { $('img.spinner').hide(); }
            }
        });
    }

    // triggers ----------------------------------------------------------------------------------------------------------------
    $("#result tr.entry").live('click',function(e) {
        // console.log('fooooo %o',$(this).attr('rel'));
        var docuid = $(this).attr('rel');
        show(docuid);
    });

    $('ul.panellist img#add_bookmark').bind('click',function(e) {
        var urlQuerySearch = window.location.toString().match(/\/s\/([^\/]+)/);
        var urlQueryDocUID = window.location.toString().match(/\/d\/([\w\d\-\/]+)/);

        $('ul.panellist ul.bookmarklist').append(['<li><a href="',window.location.pathname,'"><span class="docuid">',urlQueryDocUID[1],'</span><span class="search">',urlQuerySearch[1],'</span></a></li>'].join(''));
    });

    $("ul.panellist ul.historylist li").live('click', function(e) {
        $('input[name=q]').val($(this).text().trim());
        var query = $('input[name=q]').val();
        window.history.pushState({},'BeLawsHub', '/s/' + query );
        submit();
        $(".mainview").empty();
    });

    $("input[type=submit]").bind('click', function(e) {
        e.preventDefault();
        submit();
        $(".mainview").empty();
        var query = $('input[name=q]').val();
        $('ul.panellist ul.historylist').append(['<li>',query,'</li>'].join(''));
        window.history.pushState({},'BeLawsHub', '/s/' + query );
        return false;
    });

    $("form").bind("submit",function(e) {
        e.preventDefault();
        submit();
        $(".mainview").empty();
        var query = $('input[name=q]').val();
        $('ul.panellist ul.historylist').append(['<li>',query,'</li>'].join(''));
        window.history.pushState({},'BeLawsHub', '/s/' + query );
        return false;
    });
});
