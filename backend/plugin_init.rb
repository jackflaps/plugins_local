require_relative 'lib/denver_marc_serializer'
require_relative 'lib/du_marc_exporter'
require_relative 'lib/denver_patches'

MARCSerializer.add_decorator(DenverMARCSerializer)
