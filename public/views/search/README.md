## About these pages

These are customizations for how to display summaries of search results of various data model types, in addition to the titles (which display by default). Each works in the same way:

* The search result's JSON object is stored as a variable
* Each search result is extended to include a selection of metadata from the JSON object. Here this includes its creator, an abstract or summary (if available), and the component ID or digital object handle.

These are pretty straightforward to create once you know where they live in the plugin directory. Provided as an example of how one might go about doing it; we haven't done any styling yet, or any investigation of how fields with multiple values might be presented here.
