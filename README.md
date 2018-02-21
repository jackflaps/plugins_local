# plugins/local

Local plugins for ArchivesSpace at DU

Our locals do three things:

1. Branding
2. Extend the resource_tree content model to display the component IDs in the third column, for easier tree navigation for our archivists
3. Extend the public search result summary to provide additional metadata about Resources, Archival Objects, and Digital Objects
4. Add rows to the component toolbar for Archival Objects to allow for MODS export and linking to digital objects, provided the [ao_mods](https://github.com/duspeccoll/ao_mods) and [item_linker](https://github.com/duspeccoll/item_linker) plugins are active

(3) in particular is fairly undeveloped, and hasn't been styled in any way; I offer it as an example of how one might extend the results summary on their public site. I expect to revise it further as we do some rudimentary UX testing amongst the archivists here.
