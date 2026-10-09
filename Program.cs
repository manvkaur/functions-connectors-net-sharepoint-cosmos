// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using Microsoft.Extensions.Hosting;

new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .Build()
    .Run();
